<?php
declare(strict_types=1);

/**
 * Jadwal pakan per siklus dan pengingat harian.
 * Jadwal = jam dan jumlah pakan yang direncanakan; pengingat membandingkannya dengan
 * catatan pakan hari ini untuk menentukan mana yang sudah, waktunya, terlambat, atau menunggu.
 */
class JadwalController
{
    /** Toleransi (menit) setelah jam jadwal sebelum dianggap terlambat. */
    private const TOLERANSI_MENIT = 30;

    /** GET /siklus/{id}/jadwal-pakan */
    public function index(array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        $stmt = Database::pdo()->prepare('SELECT * FROM jadwal_pakan WHERE siklus_id = ? ORDER BY jam, id');
        $stmt->execute([$siklus['id']]);
        Response::json(['jadwal' => array_map([$this, 'format'], $stmt->fetchAll())]);
    }

    /** POST /siklus/{id}/jadwal-pakan  {jam:"07:00", jumlah_kg:12.5} */
    public function store(array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        $in = $this->validasi(Request::json(), false);

        $pdo = Database::pdo();
        $pdo->prepare('INSERT INTO jadwal_pakan (siklus_id, jam, jumlah_kg, aktif) VALUES (?, ?, ?, ?)')
            ->execute([$siklus['id'], $in['jam'], $in['jumlah_kg'], $in['aktif']]);
        $row = $this->ambil((int) $pdo->lastInsertId(), (int) $siklus['id']);
        Response::json(['jadwal' => $this->format($row)], 201);
    }

    /** PUT /siklus/{id}/jadwal-pakan/{jid}  {jam, jumlah_kg, aktif?} */
    public function update(array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        $jid = Valid::idParam($params, 'jid');
        $lama = $this->ambil($jid, (int) $siklus['id']);
        $in = $this->validasi(Request::json(), true, (int) $lama['aktif']);

        Database::pdo()->prepare('UPDATE jadwal_pakan SET jam = ?, jumlah_kg = ?, aktif = ? WHERE id = ? AND siklus_id = ?')
            ->execute([$in['jam'], $in['jumlah_kg'], $in['aktif'], $jid, $siklus['id']]);
        Response::json(['jadwal' => $this->format($this->ambil($jid, (int) $siklus['id']))]);
    }

    /** DELETE /siklus/{id}/jadwal-pakan/{jid} */
    public function destroy(array $params = []): void
    {
        $user = Auth::user();
        $siklus = Milik::siklus(Valid::idParam($params), (int) $user['sub']);
        $jid = Valid::idParam($params, 'jid');
        $this->ambil($jid, (int) $siklus['id']);
        Database::pdo()->prepare('DELETE FROM jadwal_pakan WHERE id = ? AND siklus_id = ?')
            ->execute([$jid, $siklus['id']]);
        Response::json(['message' => 'Jadwal dihapus']);
    }

    /**
     * GET /pengingat/hari-ini
     * Seluruh jadwal aktif dari siklus aktif milik pengguna, lengkap dengan status hari ini.
     * Pemberian pakan hari ini dicocokkan berurutan: N catatan pakan = N jadwal paling awal sudah dikerjakan.
     */
    public function hariIni(array $params = []): void
    {
        $user = Auth::user();
        $pdo = Database::pdo();
        $sekarang = new DateTime();
        $menitSekarang = (int) $sekarang->format('G') * 60 + (int) $sekarang->format('i');
        $hariIni = $sekarang->format('Y-m-d');

        $sik = $pdo->prepare(
            "SELECT s.id, s.siklus_ke, u.nama AS unit_nama, k.nama AS komoditas
             FROM siklus s
             JOIN unit_budidaya u ON u.id = s.unit_id
             JOIN komoditas k ON k.id = s.komoditas_id
             WHERE s.user_id = ? AND s.status = 'aktif'
             ORDER BY u.nama"
        );
        $sik->execute([$user['sub']]);

        $jad = $pdo->prepare('SELECT * FROM jadwal_pakan WHERE siklus_id = ? AND aktif = 1 ORDER BY jam, id');
        $cnt = $pdo->prepare('SELECT COUNT(*) FROM catatan_pakan WHERE siklus_id = ? AND DATE(waktu) = ?');

        $out = [];
        $belum = 0;
        foreach ($sik->fetchAll() as $s) {
            $jad->execute([$s['id']]);
            $slot = $jad->fetchAll();
            if (!$slot) {
                continue;
            }
            $cnt->execute([$s['id'], $hariIni]);
            $sudah = (int) $cnt->fetchColumn();

            $items = [];
            foreach ($slot as $i => $j) {
                $menitJadwal = (int) substr((string) $j['jam'], 0, 2) * 60 + (int) substr((string) $j['jam'], 3, 2);
                if ($i < $sudah) {
                    $status = 'sudah';
                } elseif ($menitSekarang > $menitJadwal + self::TOLERANSI_MENIT) {
                    $status = 'terlambat';
                } elseif ($menitSekarang >= $menitJadwal) {
                    $status = 'waktunya';
                } else {
                    $status = 'menunggu';
                }
                if ($status !== 'sudah') {
                    $belum++;
                }
                $items[] = [
                    'jadwal_id' => (int) $j['id'],
                    'jam'       => substr((string) $j['jam'], 0, 5),
                    'jumlah_kg' => (float) $j['jumlah_kg'],
                    'status'    => $status,
                ];
            }
            $out[] = [
                'siklus_id' => (int) $s['id'],
                'label'     => $s['unit_nama'] . ' · Siklus ' . $s['siklus_ke'],
                'komoditas' => $s['komoditas'],
                'jadwal'    => $items,
            ];
        }

        Response::json([
            'tanggal'     => $hariIni,
            'jam_server'  => $sekarang->format('H:i'),
            'belum_total' => $belum,
            'pengingat'   => $out,
        ]);
    }

    private function validasi(array $in, bool $update, int $aktifLama = 1): array
    {
        $errors = [];
        $jam = trim((string) ($in['jam'] ?? ''));
        if (!preg_match('/^([01]\d|2[0-3]):[0-5]\d$/', $jam)) {
            $errors['jam'] = 'Format jam HH:MM (24 jam), contoh 07:00';
        }
        $kg = Valid::number($in['jumlah_kg'] ?? null);
        if ($kg === null || $kg <= 0 || $kg > 99999) {
            $errors['jumlah_kg'] = 'Jumlah pakan harus angka lebih dari 0 (kg)';
        }
        $aktif = $update ? $aktifLama : 1;
        if (array_key_exists('aktif', $in)) {
            $aktif = filter_var($in['aktif'], FILTER_VALIDATE_BOOLEAN) ? 1 : 0;
        }
        if ($errors) {
            Response::error('Data tidak valid', 422, $errors);
        }
        return ['jam' => $jam . ':00', 'jumlah_kg' => $kg, 'aktif' => $aktif];
    }

    private function ambil(int $jid, int $siklusId): array
    {
        $stmt = Database::pdo()->prepare('SELECT * FROM jadwal_pakan WHERE id = ? AND siklus_id = ?');
        $stmt->execute([$jid, $siklusId]);
        $row = $stmt->fetch();
        if (!$row) {
            Response::error('Jadwal tidak ditemukan', 404);
        }
        return $row;
    }

    private function format(array $r): array
    {
        return [
            'id'        => (int) $r['id'],
            'jam'       => substr((string) $r['jam'], 0, 5),
            'jumlah_kg' => (float) $r['jumlah_kg'],
            'aktif'     => (int) $r['aktif'] === 1,
        ];
    }
}
