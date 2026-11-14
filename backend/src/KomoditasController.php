<?php
declare(strict_types=1);

class KomoditasController
{
    /** GET /komoditas : daftar komoditas aktif (untuk pilihan di form siklus) */
    public function index(array $params = []): void
    {
        Auth::user();
        $rows = Database::pdo()->query(
            'SELECT id, nama, jenis, durasi_panen_hari, target_bobot_panen_g, fcr_standar_maks, sr_standar_min
             FROM komoditas WHERE aktif = 1 ORDER BY id'
        )->fetchAll();

        $data = array_map(function (array $r): array {
            return [
                'id'                   => (int) $r['id'],
                'nama'                 => $r['nama'],
                'jenis'                => $r['jenis'],
                'durasi_panen_hari'    => (int) $r['durasi_panen_hari'],
                'target_bobot_panen_g' => (float) $r['target_bobot_panen_g'],
                'fcr_standar_maks'     => (float) $r['fcr_standar_maks'],
                'sr_standar_min'       => (float) $r['sr_standar_min'],
            ];
        }, $rows);

        Response::json(['komoditas' => $data]);
    }
}
