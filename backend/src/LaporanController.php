<?php
declare(strict_types=1);

/** Laporan lintas siklus milik pengguna. */
class LaporanController
{
    /**
     * GET /laporan/perbandingan?komoditas_id=
     * Satu baris per siklus (terlama dulu) dengan SR, FCR, umur, dan laba rugi,
     * ditambah rata-rata dan siklus terbaik dari siklus yang sudah selesai.
     */
    public function perbandingan(array $params = []): void
    {
        $user = Auth::user();
        $sql = "SELECT s.id, s.siklus_ke, s.status, s.tanggal_mulai,
                       u.nama AS unit_nama, k.id AS komoditas_id, k.nama AS komoditas,
                       k.fcr_standar_maks, k.sr_standar_min,
                       r.umur_hari, r.populasi_awal, r.sr_persen, r.fcr,
                       l.total_modal, l.total_pendapatan, l.laba_rugi
                FROM siklus s
                JOIN unit_budidaya u ON u.id = s.unit_id
                JOIN komoditas k ON k.id = s.komoditas_id
                JOIN v_ringkasan_siklus r ON r.siklus_id = s.id
                JOIN v_laba_rugi_siklus l ON l.siklus_id = s.id
                WHERE s.user_id = ?";
        $args = [$user['sub']];

        if (isset($_GET['komoditas_id']) && $_GET['komoditas_id'] !== '') {
            $kid = Valid::posInt($_GET['komoditas_id']);
            if ($kid === null) {
                Response::error('Parameter komoditas_id tidak valid', 422);
            }
            $sql .= ' AND s.komoditas_id = ?';
            $args[] = $kid;
        }
        $sql .= ' ORDER BY s.tanggal_mulai, s.id';

        $stmt = Database::pdo()->prepare($sql);
        $stmt->execute($args);

        $f = function (?string $v): ?float {
            return $v !== null ? (float) $v : null;
        };
        $siklus = array_map(function (array $r) use ($f): array {
            return [
                'id'               => (int) $r['id'],
                'label'            => $r['unit_nama'] . ' · Siklus ' . $r['siklus_ke'],
                'unit_nama'        => $r['unit_nama'],
                'siklus_ke'        => (int) $r['siklus_ke'],
                'komoditas_id'     => (int) $r['komoditas_id'],
                'komoditas'        => $r['komoditas'],
                'status'           => $r['status'],
                'tanggal_mulai'    => $r['tanggal_mulai'],
                'umur_hari'        => (int) $r['umur_hari'],
                'populasi_awal'    => (int) $r['populasi_awal'],
                'sr_persen'        => $f($r['sr_persen']),
                'fcr'              => $f($r['fcr']),
                'fcr_standar_maks' => (float) $r['fcr_standar_maks'],
                'sr_standar_min'   => (float) $r['sr_standar_min'],
                'total_modal'      => (float) $r['total_modal'],
                'total_pendapatan' => (float) $r['total_pendapatan'],
                'laba_rugi'        => (float) $r['laba_rugi'],
            ];
        }, $stmt->fetchAll());

        // Ringkasan hanya dari siklus yang sudah selesai: siklus berjalan belum bisa dibandingkan adil.
        $selesai = array_values(array_filter($siklus, function (array $s): bool {
            return $s['status'] === 'selesai';
        }));
        $rata = function (array $rows, string $key): ?float {
            $v = array_filter(array_column($rows, $key), function ($x): bool {
                return $x !== null;
            });
            return $v ? round(array_sum($v) / count($v), 2) : null;
        };

        $terbaik = null;
        foreach ($selesai as $s) {
            if ($terbaik === null || $s['laba_rugi'] > $terbaik['laba_rugi']) {
                $terbaik = $s;
            }
        }

        Response::json([
            'siklus'    => $siklus,
            'ringkasan' => [
                'jumlah_selesai'   => count($selesai),
                'rata_sr_persen'   => $rata($selesai, 'sr_persen'),
                'rata_fcr'         => $rata($selesai, 'fcr'),
                'total_laba_rugi'  => round(array_sum(array_column($selesai, 'laba_rugi')), 2),
                'terbaik'          => $terbaik ? ['id' => $terbaik['id'], 'label' => $terbaik['label'], 'laba_rugi' => $terbaik['laba_rugi']] : null,
            ],
        ]);
    }
}
