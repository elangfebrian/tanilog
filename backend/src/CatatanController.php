<?php
declare(strict_types=1);

/**
 * Catatan harian di dalam sebuah siklus: pakan, kematian, sampling bobot.
 * Ketiganya punya pola yang sama (daftar, tambah, ubah, hapus), hanya kolomnya berbeda,
 * jadi satu controller melayani ketiganya lewat parameter $jenis.
 */
class CatatanController
{
    private const TABEL = [
        'pakan'    => 'catatan_pakan',
        'kematian' => 'catatan_kematian',
        'sampling' => 'sampling_bobot',
    ];

    /** GET /siklus/{id}/{jenis} */
    public function index(string $jenis, array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);

        $tabel = self::TABEL[$jenis];
        $urut = $jenis === 'pakan' ? 'waktu' : 'tanggal';
        $stmt = Database::pdo()->prepare("SELECT * FROM $tabel WHERE siklus_id = ? ORDER BY $urut DESC, id DESC");
        $stmt->execute([$siklus['id']]);
        $rows = array_map(function (array $r) use ($jenis): array {
            return $this->format($jenis, $r);
        }, $stmt->fetchAll());

        $out = [$jenis => $rows];
        if ($jenis === 'pakan') {
            $out['total_kg'] = round(array_sum(array_column($rows, 'jumlah_kg')), 2);
        } elseif ($jenis === 'kematian') {
            $out['total_ekor'] = (int) array_sum(array_column($rows, 'jumlah'));
        }
        Response::json($out);
    }

    /** POST /siklus/{id}/{jenis} */
    public function store(string $jenis, array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        if ($siklus['status'] !== 'aktif') {
            Response::error('Siklus sudah ditutup. Aktifkan kembali untuk menambah catatan.', 409);
        }

        $data = $this->validasi($jenis, Request::json(), $siklus, null);

        $kolom = array_keys($data);
        $sql = sprintf(
            'INSERT INTO %s (siklus_id, %s) VALUES (?, %s)',
            self::TABEL[$jenis],
            implode(', ', $kolom),
            implode(', ', array_fill(0, count($kolom), '?'))
        );
        $pdo = Database::pdo();
        $pdo->prepare($sql)->execute(array_merge([$siklus['id']], array_values($data)));

        $row = $this->ambil($jenis, (int) $pdo->lastInsertId(), (int) $siklus['id']);
        Response::json([
            'catatan'   => $this->format($jenis, $row),
            'ringkasan' => $this->ringkas((int) $siklus['id']),
        ], 201);
    }

    /** PUT /siklus/{id}/{jenis}/{cid} : kirim ulang seluruh isian catatan */
    public function update(string $jenis, array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        $cid = Valid::idParam($params, 'cid');
        $this->ambil($jenis, $cid, (int) $siklus['id']);   // 404 bila bukan catatan siklus ini

        $data = $this->validasi($jenis, Request::json(), $siklus, $cid);

        $set = implode(', ', array_map(function (string $k): string {
            return $k . ' = ?';
        }, array_keys($data)));
        $sql = sprintf('UPDATE %s SET %s WHERE id = ? AND siklus_id = ?', self::TABEL[$jenis], $set);
        Database::pdo()->prepare($sql)->execute(array_merge(array_values($data), [$cid, $siklus['id']]));

        Response::json([
            'catatan'   => $this->format($jenis, $this->ambil($jenis, $cid, (int) $siklus['id'])),
            'ringkasan' => $this->ringkas((int) $siklus['id']),
        ]);
    }

    /** DELETE /siklus/{id}/{jenis}/{cid} */
    public function destroy(string $jenis, array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        $cid = Valid::idParam($params, 'cid');
        $this->ambil($jenis, $cid, (int) $siklus['id']);

        Database::pdo()
            ->prepare('DELETE FROM ' . self::TABEL[$jenis] . ' WHERE id = ? AND siklus_id = ?')
            ->execute([$cid, $siklus['id']]);

        Response::json(['message' => 'Catatan dihapus', 'ringkasan' => $this->ringkas((int) $siklus['id'])]);
    }

    // ------------------------------------------------------------------

    /** Memeriksa isian dan mengembalikan pasangan kolom => nilai yang siap disimpan. */
    private function validasi(string $jenis, array $in, array $siklus, ?int $kecualiId): array
    {
        $errors = [];
        $data = [];

        if ($jenis === 'pakan') {
            $waktu = array_key_exists('waktu', $in) ? Valid::datetime($in['waktu']) : date('Y-m-d H:i:s');
            if ($waktu === null) {
                $errors['waktu'] = 'Format waktu YYYY-MM-DD HH:MM';
            } else {
                $this->cekTanggal($waktu, $siklus, $errors, 'waktu');
            }
            $kg = Valid::number($in['jumlah_kg'] ?? null);
            if ($kg === null || $kg <= 0 || $kg > 100000) {
                $errors['jumlah_kg'] = 'Jumlah pakan harus lebih dari 0 (kg)';
            }
            $data = ['waktu' => $waktu, 'jumlah_kg' => $kg, 'catatan' => $this->teks($in, 'catatan', 255, $errors)];
        } elseif ($jenis === 'kematian') {
            $tgl = $this->tanggal($in, $siklus, $errors);
            $jumlah = Valid::posInt($in['jumlah'] ?? null);
            if ($jumlah === null) {
                $errors['jumlah'] = 'Jumlah harus bilangan bulat positif';
            } else {
                $sql = 'SELECT COALESCE(SUM(jumlah), 0) FROM catatan_kematian WHERE siklus_id = ?';
                $args = [$siklus['id']];
                if ($kecualiId !== null) {
                    $sql .= ' AND id <> ?';
                    $args[] = $kecualiId;
                }
                $stmt = Database::pdo()->prepare($sql);
                $stmt->execute($args);
                $lain = (int) $stmt->fetchColumn();
                if ($lain + $jumlah > (int) $siklus['populasi_awal']) {
                    $errors['jumlah'] = sprintf(
                        'Total kematian (%d) melebihi populasi awal (%d)',
                        $lain + $jumlah,
                        $siklus['populasi_awal']
                    );
                }
            }
            $data = ['tanggal' => $tgl, 'jumlah' => $jumlah, 'penyebab' => $this->teks($in, 'penyebab', 120, $errors)];
        } else {   // sampling
            $tgl = $this->tanggal($in, $siklus, $errors);
            $sampel = 1;
            if (array_key_exists('jumlah_sampel', $in)) {
                $sampel = Valid::posInt($in['jumlah_sampel']);
                if ($sampel === null || $sampel > 65535) {
                    $errors['jumlah_sampel'] = 'Jumlah sampel harus bilangan bulat positif';
                }
            }
            $bobot = Valid::number($in['bobot_rata_g'] ?? null);
            if ($bobot === null || $bobot <= 0 || $bobot > 100000) {
                $errors['bobot_rata_g'] = 'Bobot rata-rata harus lebih dari 0 (gram per ekor)';
            }
            $data = ['tanggal' => $tgl, 'jumlah_sampel' => $sampel, 'bobot_rata_g' => $bobot];
        }

        if ($errors) {
            Response::error('Data tidak valid', 422, $errors);
        }
        return $data;
    }

    /** Tanggal 'YYYY-MM-DD'; bila tidak dikirim dipakai hari ini. */
    private function tanggal(array $in, array $siklus, array &$errors): ?string
    {
        $tgl = array_key_exists('tanggal', $in) ? $in['tanggal'] : date('Y-m-d');
        if (!Valid::date($tgl)) {
            $errors['tanggal'] = 'Format tanggal YYYY-MM-DD';
            return null;
        }
        $this->cekTanggal($tgl, $siklus, $errors, 'tanggal');
        return $tgl;
    }

    /** Tidak boleh sebelum siklus dimulai atau lebih dari besok (menangkap salah ketik tahun). */
    private function cekTanggal(string $nilai, array $siklus, array &$errors, string $field): void
    {
        $hari = substr($nilai, 0, 10);
        if ($hari < $siklus['tanggal_mulai']) {
            $errors[$field] = 'Tidak boleh sebelum tanggal mulai siklus (' . $siklus['tanggal_mulai'] . ')';
        } elseif ($hari > date('Y-m-d', strtotime('+1 day'))) {
            $errors[$field] = 'Tidak boleh lebih dari besok';
        }
    }

    /** Teks opsional dengan batas panjang; kosong menjadi null. */
    private function teks(array $in, string $kunci, int $maks, array &$errors): ?string
    {
        if (!isset($in[$kunci])) {
            return null;
        }
        $t = trim((string) $in[$kunci]);
        if (mb_strlen($t) > $maks) {
            $errors[$kunci] = "Maksimal $maks karakter";
        }
        return $t !== '' ? $t : null;
    }

    private function ambil(string $jenis, int $id, int $siklusId): array
    {
        $stmt = Database::pdo()->prepare('SELECT * FROM ' . self::TABEL[$jenis] . ' WHERE id = ? AND siklus_id = ?');
        $stmt->execute([$id, $siklusId]);
        $row = $stmt->fetch();
        if (!$row) {
            Response::error('Catatan tidak ditemukan', 404);
        }
        return $row;
    }

    private function format(string $jenis, array $r): array
    {
        if ($jenis === 'pakan') {
            return ['id' => (int) $r['id'], 'waktu' => $r['waktu'], 'jumlah_kg' => (float) $r['jumlah_kg'], 'catatan' => $r['catatan']];
        }
        if ($jenis === 'kematian') {
            return ['id' => (int) $r['id'], 'tanggal' => $r['tanggal'], 'jumlah' => (int) $r['jumlah'], 'penyebab' => $r['penyebab']];
        }
        return [
            'id'            => (int) $r['id'],
            'tanggal'       => $r['tanggal'],
            'jumlah_sampel' => (int) $r['jumlah_sampel'],
            'bobot_rata_g'  => (float) $r['bobot_rata_g'],
        ];
    }

    /** Angka siklus terbaru setelah ada perubahan catatan (untuk pratinjau di layar). */
    private function ringkas(int $siklusId): array
    {
        $stmt = Database::pdo()->prepare(
            'SELECT populasi_hidup, total_mati, sr_persen, total_pakan_kg, bobot_terakhir_g, fcr
             FROM v_ringkasan_siklus WHERE siklus_id = ?'
        );
        $stmt->execute([$siklusId]);
        $r = $stmt->fetch();
        return [
            'populasi_hidup'   => (int) $r['populasi_hidup'],
            'total_mati'       => (int) $r['total_mati'],
            'sr_persen'        => $r['sr_persen'] !== null ? (float) $r['sr_persen'] : null,
            'total_pakan_kg'   => (float) $r['total_pakan_kg'],
            'bobot_terakhir_g' => (float) $r['bobot_terakhir_g'],
            'fcr'              => $r['fcr'] !== null ? (float) $r['fcr'] : null,
        ];
    }
}
