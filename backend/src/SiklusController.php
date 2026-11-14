<?php
declare(strict_types=1);

/** Siklus budidaya milik pengguna: daftar, buat, detail + ringkasan, ubah, hapus. */
class SiklusController
{
    private const STATUS = ['aktif', 'selesai', 'gagal'];

    /** GET /siklus?status=aktif|selesai|gagal */
    public function index(array $params = []): void
    {
        $user = Auth::user();
        $status = isset($_GET['status']) ? (string) $_GET['status'] : '';
        if ($status !== '' && !in_array($status, self::STATUS, true)) {
            Response::error("Parameter status harus 'aktif', 'selesai', atau 'gagal'", 422);
        }

        $sql = "SELECT s.id, s.siklus_ke, s.tanggal_mulai, s.status, s.populasi_awal,
                       u.nama AS unit_nama, u.tipe AS unit_tipe, k.nama AS komoditas,
                       r.umur_hari, r.populasi_hidup, r.sr_persen, r.total_pakan_kg,
                       r.bobot_terakhir_g, r.fcr
                FROM siklus s
                JOIN unit_budidaya u ON u.id = s.unit_id
                JOIN komoditas k ON k.id = s.komoditas_id
                JOIN v_ringkasan_siklus r ON r.siklus_id = s.id
                WHERE s.user_id = ?";
        $args = [$user['sub']];
        if ($status !== '') {
            $sql .= ' AND s.status = ?';
            $args[] = $status;
        }
        $sql .= ' ORDER BY s.tanggal_mulai DESC, s.id DESC';

        $stmt = Database::pdo()->prepare($sql);
        $stmt->execute($args);

        $data = array_map(function (array $r): array {
            return [
                'id'               => (int) $r['id'],
                'siklus_ke'        => (int) $r['siklus_ke'],
                'unit_nama'        => $r['unit_nama'],
                'unit_tipe'        => $r['unit_tipe'],
                'komoditas'        => $r['komoditas'],
                'status'           => $r['status'],
                'tanggal_mulai'    => $r['tanggal_mulai'],
                'umur_hari'        => (int) $r['umur_hari'],
                'populasi_awal'    => (int) $r['populasi_awal'],
                'populasi_hidup'   => (int) $r['populasi_hidup'],
                'sr_persen'        => $r['sr_persen'] !== null ? (float) $r['sr_persen'] : null,
                'total_pakan_kg'   => (float) $r['total_pakan_kg'],
                'bobot_terakhir_g' => (float) $r['bobot_terakhir_g'],
                'fcr'              => $r['fcr'] !== null ? (float) $r['fcr'] : null,
            ];
        }, $stmt->fetchAll());

        Response::json(['siklus' => $data]);
    }

    /** POST /siklus  {unit_id, komoditas_id, tanggal_mulai, populasi_awal, bobot_awal_g?, catatan?} */
    public function store(array $params = []): void
    {
        $user = Auth::user();
        $userId = (int) $user['sub'];
        $in = Request::json();
        $errors = [];

        $unitId = Valid::posInt($in['unit_id'] ?? null);
        $komId = Valid::posInt($in['komoditas_id'] ?? null);
        $tgl = $in['tanggal_mulai'] ?? null;
        $populasi = Valid::posInt($in['populasi_awal'] ?? null);
        $bobotAwal = 0.0;
        $catatan = isset($in['catatan']) ? trim((string) $in['catatan']) : '';

        if ($unitId === null) {
            $errors['unit_id'] = 'Pilih kolam/kandang';
        }
        if ($komId === null) {
            $errors['komoditas_id'] = 'Pilih komoditas';
        }
        if (!Valid::date($tgl)) {
            $errors['tanggal_mulai'] = 'Format tanggal YYYY-MM-DD';
        }
        if ($populasi === null) {
            $errors['populasi_awal'] = 'Populasi awal harus bilangan bulat positif';
        }
        if (isset($in['bobot_awal_g']) && $in['bobot_awal_g'] !== '') {
            $b = Valid::number($in['bobot_awal_g']);
            if ($b === null || $b < 0) {
                $errors['bobot_awal_g'] = 'Bobot awal harus angka 0 atau lebih (gram)';
            } else {
                $bobotAwal = $b;
            }
        }
        if (mb_strlen($catatan) > 255) {
            $errors['catatan'] = 'Catatan maksimal 255 karakter';
        }
        if ($errors) {
            Response::error('Data tidak valid', 422, $errors);
        }

        $pdo = Database::pdo();

        $unit = $pdo->prepare('SELECT id FROM unit_budidaya WHERE id = ? AND user_id = ?');
        $unit->execute([$unitId, $userId]);
        if (!$unit->fetch()) {
            Response::error('Unit tidak ditemukan', 404);
        }

        $kom = $pdo->prepare('SELECT id FROM komoditas WHERE id = ? AND aktif = 1');
        $kom->execute([$komId]);
        if (!$kom->fetch()) {
            Response::error('Komoditas tidak ditemukan', 404);
        }

        if ($this->unitPunyaSiklusAktif($unitId, null)) {
            Response::error('Unit ini masih punya siklus aktif. Selesaikan dulu sebelum membuat siklus baru.', 409);
        }

        $ke = $pdo->prepare('SELECT COALESCE(MAX(siklus_ke), 0) + 1 FROM siklus WHERE unit_id = ?');
        $ke->execute([$unitId]);
        $siklusKe = (int) $ke->fetchColumn();

        try {
            $ins = $pdo->prepare(
                'INSERT INTO siklus (user_id, unit_id, komoditas_id, siklus_ke, tanggal_mulai, populasi_awal, bobot_awal_g, catatan)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
            );
            $ins->execute([$userId, $unitId, $komId, $siklusKe, $tgl, $populasi, $bobotAwal, $catatan !== '' ? $catatan : null]);
        } catch (PDOException $e) {
            if ($e->getCode() === '23000') {
                Response::error('Siklus bentrok dengan permintaan lain, coba lagi', 409);
            }
            throw $e;
        }

        Response::json($this->detail((int) $pdo->lastInsertId(), $userId), 201);
    }

    /** GET /siklus/{id} : data siklus + ringkasan (SR, FCR, estimasi panen) + keuangan */
    public function show(array $params = []): void
    {
        $user = Auth::user();
        $id = Valid::idParam($params);
        Response::json($this->detail($id, (int) $user['sub']));
    }

    /**
     * PUT /siklus/{id} : ubah sebagian field (kirim hanya yang diubah)
     * tanggal_mulai, populasi_awal, bobot_awal_g, catatan, status, tanggal_selesai
     */
    public function update(array $params = []): void
    {
        $user = Auth::user();
        $userId = (int) $user['sub'];
        $id = Valid::idParam($params);
        $now = $this->baris($id, $userId);
        $in = Request::json();

        $set = [];
        $args = [];
        $errors = [];

        if (array_key_exists('tanggal_mulai', $in)) {
            if (!Valid::date($in['tanggal_mulai'])) {
                $errors['tanggal_mulai'] = 'Format tanggal YYYY-MM-DD';
            } else {
                $set[] = 'tanggal_mulai = ?';
                $args[] = $in['tanggal_mulai'];
            }
        }
        if (array_key_exists('populasi_awal', $in)) {
            $p = Valid::posInt($in['populasi_awal']);
            if ($p === null) {
                $errors['populasi_awal'] = 'Populasi awal harus bilangan bulat positif';
            } else {
                $mati = $this->totalMati($id);
                if ($p < $mati) {
                    $errors['populasi_awal'] = "Tidak boleh kurang dari total kematian tercatat ($mati)";
                } else {
                    $set[] = 'populasi_awal = ?';
                    $args[] = $p;
                }
            }
        }
        if (array_key_exists('bobot_awal_g', $in)) {
            $b = Valid::number($in['bobot_awal_g']);
            if ($b === null || $b < 0) {
                $errors['bobot_awal_g'] = 'Bobot awal harus angka 0 atau lebih (gram)';
            } else {
                $set[] = 'bobot_awal_g = ?';
                $args[] = $b;
            }
        }
        if (array_key_exists('catatan', $in)) {
            $c = trim((string) $in['catatan']);
            if (mb_strlen($c) > 255) {
                $errors['catatan'] = 'Catatan maksimal 255 karakter';
            } else {
                $set[] = 'catatan = ?';
                $args[] = $c !== '' ? $c : null;
            }
        }

        $statusBaru = $now['status'];
        if (array_key_exists('status', $in)) {
            if (!in_array($in['status'], self::STATUS, true)) {
                $errors['status'] = "Status harus 'aktif', 'selesai', atau 'gagal'";
            } else {
                $statusBaru = $in['status'];
            }
        }
        $tglSelesai = $now['tanggal_selesai'];
        if (array_key_exists('tanggal_selesai', $in)) {
            if ($in['tanggal_selesai'] !== null && !Valid::date($in['tanggal_selesai'])) {
                $errors['tanggal_selesai'] = 'Format tanggal YYYY-MM-DD';
            } else {
                $tglSelesai = $in['tanggal_selesai'];
            }
        }

        if ($errors) {
            Response::error('Data tidak valid', 422, $errors);
        }

        if ($statusBaru !== $now['status'] || array_key_exists('tanggal_selesai', $in)) {
            if ($statusBaru === 'aktif') {
                if ($now['status'] !== 'aktif' && $this->unitPunyaSiklusAktif((int) $now['unit_id'], $id)) {
                    Response::error('Unit ini sudah punya siklus aktif lain', 409);
                }
                $tglSelesai = null;
            } elseif ($tglSelesai === null) {
                $tglSelesai = date('Y-m-d');
            }
            $set[] = 'status = ?';
            $args[] = $statusBaru;
            $set[] = 'tanggal_selesai = ?';
            $args[] = $tglSelesai;
        }

        if (!$set) {
            Response::error('Tidak ada field yang diubah', 422);
        }

        $args[] = $id;
        $args[] = $userId;
        Database::pdo()
            ->prepare('UPDATE siklus SET ' . implode(', ', $set) . ' WHERE id = ? AND user_id = ?')
            ->execute($args);

        Response::json($this->detail($id, $userId));
    }

    /** DELETE /siklus/{id} : ikut menghapus seluruh catatan siklus tersebut */
    public function destroy(array $params = []): void
    {
        $user = Auth::user();
        $id = Valid::idParam($params);
        $this->baris($id, (int) $user['sub']);
        Database::pdo()->prepare('DELETE FROM siklus WHERE id = ? AND user_id = ?')->execute([$id, $user['sub']]);
        Response::json(['message' => 'Siklus beserta seluruh catatannya dihapus']);
    }

    // ------------------------------------------------------------------

    /** Baris mentah siklus milik pengguna, atau 404. */
    private function baris(int $id, int $userId): array
    {
        $stmt = Database::pdo()->prepare('SELECT * FROM siklus WHERE id = ? AND user_id = ?');
        $stmt->execute([$id, $userId]);
        $row = $stmt->fetch();
        if (!$row) {
            Response::error('Siklus tidak ditemukan', 404);
        }
        return $row;
    }

    private function totalMati(int $siklusId): int
    {
        $stmt = Database::pdo()->prepare('SELECT COALESCE(SUM(jumlah), 0) FROM catatan_kematian WHERE siklus_id = ?');
        $stmt->execute([$siklusId]);
        return (int) $stmt->fetchColumn();
    }

    private function unitPunyaSiklusAktif(int $unitId, ?int $kecualiSiklusId): bool
    {
        $sql = "SELECT COUNT(*) FROM siklus WHERE unit_id = ? AND status = 'aktif'";
        $args = [$unitId];
        if ($kecualiSiklusId !== null) {
            $sql .= ' AND id <> ?';
            $args[] = $kecualiSiklusId;
        }
        $stmt = Database::pdo()->prepare($sql);
        $stmt->execute($args);
        return (int) $stmt->fetchColumn() > 0;
    }

    /** Gabungan data siklus, ringkasan hitungan, dan keuangan. */
    private function detail(int $id, int $userId): array
    {
        $pdo = Database::pdo();

        $stmt = $pdo->prepare(
            'SELECT s.*, u.nama AS unit_nama, u.tipe AS unit_tipe,
                    k.nama AS komoditas_nama, k.durasi_panen_hari, k.target_bobot_panen_g,
                    k.fcr_standar_maks, k.sr_standar_min
             FROM siklus s
             JOIN unit_budidaya u ON u.id = s.unit_id
             JOIN komoditas k ON k.id = s.komoditas_id
             WHERE s.id = ? AND s.user_id = ?'
        );
        $stmt->execute([$id, $userId]);
        $s = $stmt->fetch();
        if (!$s) {
            Response::error('Siklus tidak ditemukan', 404);
        }

        $r = $pdo->prepare('SELECT * FROM v_ringkasan_siklus WHERE siklus_id = ?');
        $r->execute([$id]);
        $r = $r->fetch();

        $k = $pdo->prepare('SELECT * FROM v_laba_rugi_siklus WHERE siklus_id = ?');
        $k->execute([$id]);
        $k = $k->fetch();

        $samp = $pdo->prepare(
            'SELECT tanggal, bobot_rata_g FROM sampling_bobot WHERE siklus_id = ? ORDER BY tanggal DESC, id DESC LIMIT 1'
        );
        $samp->execute([$id]);
        $samp = $samp->fetch();

        $std = $pdo->prepare(
            'SELECT hari_ke, bobot_standar_g FROM standar_pertumbuhan WHERE komoditas_id = ? ORDER BY hari_ke'
        );
        $std->execute([$s['komoditas_id']]);
        $standar = $std->fetchAll();

        $sr = $r['sr_persen'] !== null ? (float) $r['sr_persen'] : null;
        $fcr = $r['fcr'] !== null ? (float) $r['fcr'] : null;

        $estimasi = null;
        if ($s['status'] === 'aktif') {
            $estimasi = Hitung::estimasiPanen(
                (string) $s['tanggal_mulai'],
                (int) $s['durasi_panen_hari'],
                $samp ? (float) $samp['bobot_rata_g'] : null,
                $samp ? (string) $samp['tanggal'] : null,
                $standar,
                date('Y-m-d')
            );
        }

        return [
            'siklus' => [
                'id'              => (int) $s['id'],
                'siklus_ke'       => (int) $s['siklus_ke'],
                'unit_id'         => (int) $s['unit_id'],
                'unit_nama'       => $s['unit_nama'],
                'unit_tipe'       => $s['unit_tipe'],
                'komoditas_id'    => (int) $s['komoditas_id'],
                'komoditas'       => $s['komoditas_nama'],
                'status'          => $s['status'],
                'tanggal_mulai'   => $s['tanggal_mulai'],
                'tanggal_selesai' => $s['tanggal_selesai'],
                'populasi_awal'   => (int) $s['populasi_awal'],
                'bobot_awal_g'    => (float) $s['bobot_awal_g'],
                'catatan'         => $s['catatan'],
            ],
            'ringkasan' => [
                'umur_hari'            => (int) $r['umur_hari'],
                'populasi_hidup'       => (int) $r['populasi_hidup'],
                'total_mati'           => (int) $r['total_mati'],
                'sr_persen'            => $sr,
                'sr_standar_min'       => (float) $s['sr_standar_min'],
                'sr_status'            => $sr === null ? null : ($sr >= (float) $s['sr_standar_min'] ? 'baik' : 'perlu_perhatian'),
                'total_pakan_kg'       => (float) $r['total_pakan_kg'],
                'bobot_terakhir_g'     => (float) $r['bobot_terakhir_g'],
                'target_bobot_panen_g' => (float) $s['target_bobot_panen_g'],
                'biomassa_kini_kg'     => (float) $r['biomassa_kini_kg'],
                'fcr'                  => $fcr,
                'fcr_standar_maks'     => (float) $s['fcr_standar_maks'],
                'fcr_status'           => $fcr === null ? null : ($fcr <= (float) $s['fcr_standar_maks'] ? 'baik' : 'perlu_perhatian'),
                'estimasi_panen'       => $estimasi,
            ],
            'keuangan' => [
                'total_modal'      => (float) $k['total_modal'],
                'total_pendapatan' => (float) $k['total_pendapatan'],
                'laba_rugi'        => (float) $k['laba_rugi'],
            ],
        ];
    }
}
