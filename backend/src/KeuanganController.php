<?php
declare(strict_types=1);

/** Modal, pendapatan, dan panen sebuah siklus. */
class KeuanganController
{
    private const KATEGORI_MODAL = ['bibit', 'pakan', 'obat', 'tenaga', 'listrik', 'lainnya'];

    /** GET /siklus/{id}/transaksi : daftar + total + rincian per kategori */
    public function transaksiIndex(array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        $pdo = Database::pdo();

        $stmt = $pdo->prepare('SELECT * FROM transaksi WHERE siklus_id = ? ORDER BY tanggal DESC, id DESC');
        $stmt->execute([$siklus['id']]);
        $rows = array_map([$this, 'format'], $stmt->fetchAll());

        $kat = $pdo->prepare(
            'SELECT tipe, kategori, SUM(jumlah_rp) AS total FROM transaksi
             WHERE siklus_id = ? GROUP BY tipe, kategori ORDER BY tipe, kategori'
        );
        $kat->execute([$siklus['id']]);
        $perKategori = array_map(function (array $r): array {
            return ['tipe' => $r['tipe'], 'kategori' => $r['kategori'], 'total' => (float) $r['total']];
        }, $kat->fetchAll());

        Response::json([
            'transaksi'    => $rows,
            'per_kategori' => $perKategori,
            'keuangan'     => $this->keuangan((int) $siklus['id']),
        ]);
    }

    /** POST /siklus/{id}/transaksi  {tipe, kategori, tanggal?, keterangan?, jumlah_rp} */
    public function transaksiStore(array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        $in = Request::json();
        $errors = [];

        $tipe = (string) ($in['tipe'] ?? '');
        $kategori = (string) ($in['kategori'] ?? '');
        if (!in_array($tipe, ['modal', 'pendapatan'], true)) {
            $errors['tipe'] = "Tipe harus 'modal' atau 'pendapatan'";
        } elseif ($tipe === 'modal' && !in_array($kategori, self::KATEGORI_MODAL, true)) {
            $errors['kategori'] = 'Kategori modal: ' . implode(', ', self::KATEGORI_MODAL);
        } elseif ($tipe === 'pendapatan' && $kategori !== 'penjualan') {
            $errors['kategori'] = "Kategori pendapatan hanya 'penjualan'";
        }

        $tgl = array_key_exists('tanggal', $in) ? $in['tanggal'] : date('Y-m-d');
        if (!Valid::date($tgl)) {
            $errors['tanggal'] = 'Format tanggal YYYY-MM-DD';
        } elseif ($tgl < $siklus['tanggal_mulai']) {
            $errors['tanggal'] = 'Tidak boleh sebelum tanggal mulai siklus (' . $siklus['tanggal_mulai'] . ')';
        }

        $jumlah = Valid::number($in['jumlah_rp'] ?? null);
        if ($jumlah === null || $jumlah <= 0 || $jumlah > 99999999999) {
            $errors['jumlah_rp'] = 'Jumlah harus lebih dari 0 (rupiah)';
        }

        $ket = isset($in['keterangan']) ? trim((string) $in['keterangan']) : '';
        if (mb_strlen($ket) > 150) {
            $errors['keterangan'] = 'Maksimal 150 karakter';
        }
        if ($errors) {
            Response::error('Data tidak valid', 422, $errors);
        }

        $pdo = Database::pdo();
        $pdo->prepare(
            'INSERT INTO transaksi (siklus_id, tipe, kategori, tanggal, keterangan, jumlah_rp) VALUES (?, ?, ?, ?, ?, ?)'
        )->execute([$siklus['id'], $tipe, $kategori, $tgl, $ket !== '' ? $ket : null, round($jumlah, 2)]);

        $row = $pdo->prepare('SELECT * FROM transaksi WHERE id = ?');
        $row->execute([$pdo->lastInsertId()]);
        Response::json([
            'transaksi' => $this->format($row->fetch()),
            'keuangan'  => $this->keuangan((int) $siklus['id']),
        ], 201);
    }

    /** DELETE /siklus/{id}/transaksi/{tid} */
    public function transaksiDestroy(array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        $tid = Valid::idParam($params, 'tid');

        $pdo = Database::pdo();
        $stmt = $pdo->prepare('SELECT id, panen_id FROM transaksi WHERE id = ? AND siklus_id = ?');
        $stmt->execute([$tid, $siklus['id']]);
        $row = $stmt->fetch();
        if (!$row) {
            Response::error('Transaksi tidak ditemukan', 404);
        }
        if ($row['panen_id'] !== null) {
            Response::error('Transaksi ini dibuat otomatis dari panen. Batalkan lewat DELETE /siklus/{id}/panen.', 409);
        }
        $pdo->prepare('DELETE FROM transaksi WHERE id = ?')->execute([$tid]);
        Response::json(['message' => 'Transaksi dihapus', 'keuangan' => $this->keuangan((int) $siklus['id'])]);
    }

    /** GET /siklus/{id}/panen */
    public function panenShow(array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        $panen = $this->panen((int) $siklus['id']);
        if ($panen === null) {
            Response::error('Panen belum dicatat', 404);
        }
        Response::json(['panen' => $this->formatPanen($panen), 'keuangan' => $this->keuangan((int) $siklus['id'])]);
    }

    /**
     * POST /siklus/{id}/panen  {tanggal?, jumlah_ekor, bobot_total_kg, harga_per_kg}
     * Sekaligus: mencatat pendapatan penjualan dan menutup siklus (status 'selesai').
     */
    public function panenStore(array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        if ($siklus['status'] !== 'aktif') {
            Response::error('Siklus tidak aktif, panen tidak bisa dicatat', 409);
        }
        if ($this->panen((int) $siklus['id']) !== null) {
            Response::error('Panen siklus ini sudah dicatat', 409);
        }

        $in = Request::json();
        $errors = [];

        $tgl = array_key_exists('tanggal', $in) ? $in['tanggal'] : date('Y-m-d');
        if (!Valid::date($tgl)) {
            $errors['tanggal'] = 'Format tanggal YYYY-MM-DD';
        } elseif ($tgl < $siklus['tanggal_mulai']) {
            $errors['tanggal'] = 'Tidak boleh sebelum tanggal mulai siklus (' . $siklus['tanggal_mulai'] . ')';
        } elseif ($tgl > date('Y-m-d', strtotime('+1 day'))) {
            $errors['tanggal'] = 'Tidak boleh lebih dari besok';
        }

        $stmt = Database::pdo()->prepare('SELECT populasi_hidup FROM v_ringkasan_siklus WHERE siklus_id = ?');
        $stmt->execute([$siklus['id']]);
        $hidup = (int) $stmt->fetchColumn();

        $ekor = Valid::posInt($in['jumlah_ekor'] ?? null);
        if ($ekor === null) {
            $errors['jumlah_ekor'] = 'Jumlah ekor harus bilangan bulat positif';
        } elseif ($ekor > $hidup) {
            $errors['jumlah_ekor'] = "Melebihi populasi hidup ($hidup ekor)";
        }
        $bobot = Valid::number($in['bobot_total_kg'] ?? null);
        if ($bobot === null || $bobot <= 0 || $bobot > 10000000) {
            $errors['bobot_total_kg'] = 'Bobot total harus lebih dari 0 (kg)';
        }
        $harga = Valid::number($in['harga_per_kg'] ?? null);
        if ($harga === null || $harga <= 0 || $harga > 100000000) {
            $errors['harga_per_kg'] = 'Harga per kg harus lebih dari 0 (rupiah)';
        }
        if ($errors) {
            Response::error('Data tidak valid', 422, $errors);
        }

        $pdo = Database::pdo();
        $pdo->beginTransaction();
        try {
            $pdo->prepare(
                'INSERT INTO panen (siklus_id, tanggal, jumlah_ekor, bobot_total_kg, harga_per_kg) VALUES (?, ?, ?, ?, ?)'
            )->execute([$siklus['id'], $tgl, $ekor, $bobot, $harga]);
            $panenId = (int) $pdo->lastInsertId();

            $pdo->prepare(
                "INSERT INTO transaksi (siklus_id, tipe, kategori, tanggal, keterangan, jumlah_rp, panen_id)
                 VALUES (?, 'pendapatan', 'penjualan', ?, ?, ?, ?)"
            )->execute([$siklus['id'], $tgl, 'Panen ' . $bobot . ' kg', round($bobot * $harga, 2), $panenId]);

            $pdo->prepare("UPDATE siklus SET status = 'selesai', tanggal_selesai = ? WHERE id = ?")
                ->execute([$tgl, $siklus['id']]);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }

        Response::json([
            'panen'    => $this->formatPanen($this->panen((int) $siklus['id'])),
            'keuangan' => $this->keuangan((int) $siklus['id']),
        ], 201);
    }

    /** DELETE /siklus/{id}/panen : batalkan panen (pendapatannya ikut terhapus, siklus aktif kembali) */
    public function panenDestroy(array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        if ($this->panen((int) $siklus['id']) === null) {
            Response::error('Panen belum dicatat', 404);
        }

        $pdo = Database::pdo();
        $lain = $pdo->prepare("SELECT COUNT(*) FROM siklus WHERE unit_id = ? AND status = 'aktif' AND id <> ?");
        $lain->execute([$siklus['unit_id'], $siklus['id']]);
        if ((int) $lain->fetchColumn() > 0) {
            Response::error('Unit ini sudah punya siklus aktif lain, siklus ini tidak bisa diaktifkan kembali', 409);
        }

        $pdo->beginTransaction();
        try {
            $pdo->prepare('DELETE FROM panen WHERE siklus_id = ?')->execute([$siklus['id']]);   // transaksi terkait ikut terhapus
            $pdo->prepare("UPDATE siklus SET status = 'aktif', tanggal_selesai = NULL WHERE id = ?")->execute([$siklus['id']]);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        Response::json(['message' => 'Panen dibatalkan, siklus aktif kembali', 'keuangan' => $this->keuangan((int) $siklus['id'])]);
    }

    // ------------------------------------------------------------------

    private function panen(int $siklusId): ?array
    {
        $stmt = Database::pdo()->prepare('SELECT * FROM panen WHERE siklus_id = ?');
        $stmt->execute([$siklusId]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    private function formatPanen(array $p): array
    {
        $ekor = (int) $p['jumlah_ekor'];
        $bobot = (float) $p['bobot_total_kg'];
        $harga = (float) $p['harga_per_kg'];
        return [
            'id'             => (int) $p['id'],
            'tanggal'        => $p['tanggal'],
            'jumlah_ekor'    => $ekor,
            'bobot_total_kg' => $bobot,
            'harga_per_kg'   => $harga,
            'bobot_rata_g'   => $ekor > 0 ? round($bobot / $ekor * 1000, 1) : null,
            'total_rp'       => round($bobot * $harga, 2),
        ];
    }

    private function format(array $r): array
    {
        return [
            'id'         => (int) $r['id'],
            'tipe'       => $r['tipe'],
            'kategori'   => $r['kategori'],
            'tanggal'    => $r['tanggal'],
            'keterangan' => $r['keterangan'],
            'jumlah_rp'  => (float) $r['jumlah_rp'],
            'dari_panen' => $r['panen_id'] !== null,
        ];
    }

    private function keuangan(int $siklusId): array
    {
        $stmt = Database::pdo()->prepare('SELECT * FROM v_laba_rugi_siklus WHERE siklus_id = ?');
        $stmt->execute([$siklusId]);
        $k = $stmt->fetch();
        return [
            'total_modal'      => (float) $k['total_modal'],
            'total_pendapatan' => (float) $k['total_pendapatan'],
            'laba_rugi'        => (float) $k['laba_rugi'],
        ];
    }
}
