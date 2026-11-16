<?php
declare(strict_types=1);

/**
 * Pengelolaan data acuan oleh admin: komoditas dan kurva standar pertumbuhan.
 * Peran dicek ulang ke database (bukan hanya dari token) agar admin yang dicabut
 * haknya langsung kehilangan akses.
 */
class AdminController
{
    private const JENIS = ['ikan', 'unggas'];

    private function admin(): void
    {
        $user = Auth::requireRole('admin');
        $stmt = Database::pdo()->prepare('SELECT role FROM users WHERE id = ?');
        $stmt->execute([$user['sub']]);
        if ($stmt->fetchColumn() !== 'admin') {
            Response::error('Anda tidak berhak mengakses ini', 403);
        }
    }

    /** GET /admin/ringkasan */
    public function ringkasan(array $params = []): void
    {
        $this->admin();
        $pdo = Database::pdo();
        $one = function (string $sql) use ($pdo): int {
            return (int) $pdo->query($sql)->fetchColumn();
        };
        Response::json([
            'peternak'       => $one("SELECT COUNT(*) FROM users WHERE role = 'peternak'"),
            'unit'           => $one('SELECT COUNT(*) FROM unit_budidaya'),
            'siklus_aktif'   => $one("SELECT COUNT(*) FROM siklus WHERE status = 'aktif'"),
            'siklus_selesai' => $one("SELECT COUNT(*) FROM siklus WHERE status = 'selesai'"),
            'komoditas'      => $one('SELECT COUNT(*) FROM komoditas WHERE aktif = 1'),
        ]);
    }

    /** GET /admin/komoditas : semua komoditas termasuk yang dinonaktifkan */
    public function komoditasIndex(array $params = []): void
    {
        $this->admin();
        $rows = Database::pdo()->query(
            'SELECT k.*,
                    (SELECT COUNT(*) FROM siklus s WHERE s.komoditas_id = k.id) AS jumlah_siklus,
                    (SELECT COUNT(*) FROM standar_pertumbuhan p WHERE p.komoditas_id = k.id) AS jumlah_titik
             FROM komoditas k ORDER BY k.id'
        )->fetchAll();
        Response::json(['komoditas' => array_map([$this, 'format'], $rows)]);
    }

    /** POST /admin/komoditas */
    public function komoditasStore(array $params = []): void
    {
        $this->admin();
        $in = $this->validasi(Request::json());
        $pdo = Database::pdo();
        try {
            $pdo->prepare(
                'INSERT INTO komoditas (nama, jenis, durasi_panen_hari, target_bobot_panen_g, fcr_standar_maks, sr_standar_min, aktif)
                 VALUES (?, ?, ?, ?, ?, ?, ?)'
            )->execute([$in['nama'], $in['jenis'], $in['durasi_panen_hari'], $in['target_bobot_panen_g'],
                        $in['fcr_standar_maks'], $in['sr_standar_min'], $in['aktif']]);
        } catch (PDOException $e) {
            $this->kembar($e);
        }
        Response::json(['komoditas' => $this->format($this->ambil((int) $pdo->lastInsertId()))], 201);
    }

    /** PUT /admin/komoditas/{id} : kirim ulang seluruh isian */
    public function komoditasUpdate(array $params = []): void
    {
        $this->admin();
        $id = Valid::idParam($params);
        $this->ambil($id);
        $in = $this->validasi(Request::json());
        try {
            Database::pdo()->prepare(
                'UPDATE komoditas SET nama = ?, jenis = ?, durasi_panen_hari = ?, target_bobot_panen_g = ?,
                        fcr_standar_maks = ?, sr_standar_min = ?, aktif = ? WHERE id = ?'
            )->execute([$in['nama'], $in['jenis'], $in['durasi_panen_hari'], $in['target_bobot_panen_g'],
                        $in['fcr_standar_maks'], $in['sr_standar_min'], $in['aktif'], $id]);
        } catch (PDOException $e) {
            $this->kembar($e);
        }
        Response::json(['komoditas' => $this->format($this->ambil($id))]);
    }

    /** GET /admin/komoditas/{id}/standar */
    public function standarIndex(array $params = []): void
    {
        $this->admin();
        $id = Valid::idParam($params);
        $this->ambil($id);
        Response::json(['standar' => $this->titik($id)]);
    }

    /**
     * PUT /admin/komoditas/{id}/standar  {standar:[{hari_ke, bobot_standar_g, pakan_standar_g?}, ...]}
     * Mengganti seluruh kurva dalam satu transaksi. Bobot harus naik seiring hari
     * karena estimasi panen mencari "umur setara" lewat interpolasi pada kurva ini.
     */
    public function standarReplace(array $params = []): void
    {
        $this->admin();
        $id = Valid::idParam($params);
        $this->ambil($id);

        $in = Request::json();
        $raw = $in['standar'] ?? null;
        if (!is_array($raw) || count($raw) < 2) {
            Response::error('Data tidak valid', 422, ['standar' => 'Minimal 2 titik (hari dan bobot)']);
        }
        if (count($raw) > 200) {
            Response::error('Data tidak valid', 422, ['standar' => 'Maksimal 200 titik']);
        }

        $titik = [];
        $errors = [];
        foreach (array_values($raw) as $i => $t) {
            $n = $i + 1;
            if (!is_array($t)) {
                $errors["titik $n"] = 'Harus berupa objek';
                continue;
            }
            $hari = Valid::number($t['hari_ke'] ?? null);
            $bobot = Valid::number($t['bobot_standar_g'] ?? null);
            if ($hari === null || $hari < 0 || $hari > 1000 || $hari != floor($hari)) {
                $errors["titik $n"] = 'hari_ke harus bilangan bulat 0 sampai 1000';
                continue;
            }
            if ($bobot === null || $bobot <= 0 || $bobot > 99999) {
                $errors["titik $n"] = 'bobot_standar_g harus angka lebih dari 0';
                continue;
            }
            $pakan = null;
            if (isset($t['pakan_standar_g']) && $t['pakan_standar_g'] !== '') {
                $pakan = Valid::number($t['pakan_standar_g']);
                if ($pakan === null || $pakan < 0) {
                    $errors["titik $n"] = 'pakan_standar_g harus angka 0 atau lebih';
                    continue;
                }
            }
            $titik[] = ['hari' => (int) $hari, 'bobot' => $bobot, 'pakan' => $pakan];
        }
        if (!$errors) {
            usort($titik, function (array $a, array $b): int {
                return $a['hari'] <=> $b['hari'];
            });
            for ($i = 1; $i < count($titik); $i++) {
                if ($titik[$i]['hari'] === $titik[$i - 1]['hari']) {
                    $errors['standar'] = 'Hari ke-' . $titik[$i]['hari'] . ' muncul lebih dari sekali';
                    break;
                }
                if ($titik[$i]['bobot'] < $titik[$i - 1]['bobot']) {
                    $errors['standar'] = 'Bobot tidak boleh turun: hari ke-' . $titik[$i]['hari'] . ' lebih ringan dari hari sebelumnya';
                    break;
                }
            }
        }
        if ($errors) {
            Response::error('Data tidak valid', 422, $errors);
        }

        $pdo = Database::pdo();
        $pdo->beginTransaction();
        try {
            $pdo->prepare('DELETE FROM standar_pertumbuhan WHERE komoditas_id = ?')->execute([$id]);
            $ins = $pdo->prepare(
                'INSERT INTO standar_pertumbuhan (komoditas_id, hari_ke, bobot_standar_g, pakan_standar_g) VALUES (?, ?, ?, ?)'
            );
            foreach ($titik as $t) {
                $ins->execute([$id, $t['hari'], $t['bobot'], $t['pakan']]);
            }
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        Response::json(['standar' => $this->titik($id)]);
    }

    private function validasi(array $in): array
    {
        $errors = [];
        $nama = trim((string) ($in['nama'] ?? ''));
        if ($nama === '' || mb_strlen($nama) > 50) {
            $errors['nama'] = 'Nama wajib diisi, maksimal 50 karakter';
        }
        $jenis = (string) ($in['jenis'] ?? '');
        if (!in_array($jenis, self::JENIS, true)) {
            $errors['jenis'] = "Jenis harus 'ikan' atau 'unggas'";
        }
        $durasi = Valid::posInt($in['durasi_panen_hari'] ?? null);
        if ($durasi === null || $durasi > 1000) {
            $errors['durasi_panen_hari'] = 'Durasi panen harus bilangan bulat 1 sampai 1000 (hari)';
        }
        $target = Valid::number($in['target_bobot_panen_g'] ?? null);
        if ($target === null || $target <= 0 || $target > 99999) {
            $errors['target_bobot_panen_g'] = 'Target bobot harus angka lebih dari 0 (gram)';
        }
        $fcr = Valid::number($in['fcr_standar_maks'] ?? null);
        if ($fcr === null || $fcr <= 0 || $fcr > 99) {
            $errors['fcr_standar_maks'] = 'FCR standar harus angka lebih dari 0 dan paling besar 99';
        }
        $sr = Valid::number($in['sr_standar_min'] ?? null);
        if ($sr === null || $sr < 0 || $sr > 100) {
            $errors['sr_standar_min'] = 'SR standar harus angka 0 sampai 100';
        }
        $aktif = 1;
        if (array_key_exists('aktif', $in)) {
            $aktif = filter_var($in['aktif'], FILTER_VALIDATE_BOOLEAN) ? 1 : 0;
        }
        if ($errors) {
            Response::error('Data tidak valid', 422, $errors);
        }
        return [
            'nama' => $nama, 'jenis' => $jenis, 'durasi_panen_hari' => $durasi,
            'target_bobot_panen_g' => $target, 'fcr_standar_maks' => $fcr,
            'sr_standar_min' => $sr, 'aktif' => $aktif,
        ];
    }

    private function ambil(int $id): array
    {
        $stmt = Database::pdo()->prepare(
            'SELECT k.*,
                    (SELECT COUNT(*) FROM siklus s WHERE s.komoditas_id = k.id) AS jumlah_siklus,
                    (SELECT COUNT(*) FROM standar_pertumbuhan p WHERE p.komoditas_id = k.id) AS jumlah_titik
             FROM komoditas k WHERE k.id = ?'
        );
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        if (!$row) {
            Response::error('Komoditas tidak ditemukan', 404);
        }
        return $row;
    }

    private function titik(int $id): array
    {
        $stmt = Database::pdo()->prepare(
            'SELECT hari_ke, bobot_standar_g, pakan_standar_g FROM standar_pertumbuhan WHERE komoditas_id = ? ORDER BY hari_ke'
        );
        $stmt->execute([$id]);
        return array_map(function (array $r): array {
            return [
                'hari_ke'         => (int) $r['hari_ke'],
                'bobot_standar_g' => (float) $r['bobot_standar_g'],
                'pakan_standar_g' => $r['pakan_standar_g'] !== null ? (float) $r['pakan_standar_g'] : null,
            ];
        }, $stmt->fetchAll());
    }

    private function format(array $r): array
    {
        return [
            'id'                   => (int) $r['id'],
            'nama'                 => $r['nama'],
            'jenis'                => $r['jenis'],
            'durasi_panen_hari'    => (int) $r['durasi_panen_hari'],
            'target_bobot_panen_g' => (float) $r['target_bobot_panen_g'],
            'fcr_standar_maks'     => (float) $r['fcr_standar_maks'],
            'sr_standar_min'       => (float) $r['sr_standar_min'],
            'aktif'                => (int) $r['aktif'] === 1,
            'jumlah_siklus'        => (int) $r['jumlah_siklus'],
            'jumlah_titik'         => (int) $r['jumlah_titik'],
        ];
    }

    private function kembar(PDOException $e): void
    {
        if ($e->getCode() === '23000') {
            Response::error('Nama komoditas sudah dipakai', 409);
        }
        throw $e;
    }
}
