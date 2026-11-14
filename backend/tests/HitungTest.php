<?php
declare(strict_types=1);

/**
 * Tes sederhana untuk perhitungan tanpa database.
 * Jalankan:  php backend/tests/HitungTest.php
 */
require __DIR__ . '/../src/Http.php';
require __DIR__ . '/../src/Helpers.php';

$gagal = 0;
function cek(string $nama, $aktual, $harapan): void
{
    global $gagal;
    $ok = $aktual === $harapan;
    if (!$ok) {
        $gagal++;
    }
    echo ($ok ? '[LULUS] ' : '[GAGAL] ') . $nama
        . ($ok ? '' : '  aktual=' . json_encode($aktual) . ' harapan=' . json_encode($harapan)) . "\n";
}

// Standar lele (sama dengan data awal di schema.sql)
$lele = [
    ['hari_ke' => 0,  'bobot_standar_g' => 5],
    ['hari_ke' => 10, 'bobot_standar_g' => 15],
    ['hari_ke' => 20, 'bobot_standar_g' => 40],
    ['hari_ke' => 30, 'bobot_standar_g' => 80],
    ['hari_ke' => 40, 'bobot_standar_g' => 120],
    ['hari_ke' => 45, 'bobot_standar_g' => 140],
    ['hari_ke' => 60, 'bobot_standar_g' => 250],
];

// --- Hitung::hariSetara
cek('umur setara 128 g = hari ke-42',        Hitung::hariSetara(128, $lele), 42.0);
cek('tepat di titik standar (80 g = hari 30)', Hitung::hariSetara(80, $lele), 30.0);
cek('lebih ringan dari titik pertama = 0',    Hitung::hariSetara(2, $lele), 0.0);
cek('lebih berat dari titik terakhir = 60',   Hitung::hariSetara(300, $lele), 60.0);
cek('standar kosong = null',                  Hitung::hariSetara(100, []), null);

// --- Hitung::estimasiPanen
$e = Hitung::estimasiPanen('2026-09-22', 60, 128.0, '2026-11-05', $lele, '2026-11-14');
cek('estimasi dengan sampling: tanggal',   $e['tanggal'], '2026-11-23');
cek('estimasi dengan sampling: sisa hari', $e['sisa_hari'], 9);
cek('estimasi dengan sampling: metode',    $e['metode'], 'kurva_standar');
cek('estimasi dengan sampling: umur setara', $e['umur_setara'], 42.0);

$e = Hitung::estimasiPanen('2026-09-22', 60, null, null, $lele, '2026-11-14');
cek('tanpa sampling: tanggal = mulai + durasi', $e['tanggal'], '2026-11-21');
cek('tanpa sampling: metode',                   $e['metode'], 'umur_standar');

$e = Hitung::estimasiPanen('2026-09-22', 60, 128.0, '2026-11-05', $lele, '2026-12-01');
cek('lewat estimasi: sisa hari negatif', $e['sisa_hari'], -8);

$e = Hitung::estimasiPanen('2026-09-22', 60, 260.0, '2026-11-10', $lele, '2026-11-14');
cek('sudah mencapai target: panen di tanggal sampling', $e['tanggal'], '2026-11-10');

// --- Valid
cek('tanggal valid',            Valid::date('2026-11-14'), true);
cek('tanggal 30 Februari',      Valid::date('2026-02-30'), false);
cek('tanggal format salah',     Valid::date('14-11-2026'), false);
cek('tanggal bukan string',     Valid::date(20261114), false);
cek('posInt 5',                 Valid::posInt(5), 5);
cek('posInt "5"',               Valid::posInt('5'), 5);
cek('posInt 5.0',               Valid::posInt(5.0), 5);
cek('posInt 0 ditolak',         Valid::posInt(0), null);
cek('posInt -3 ditolak',        Valid::posInt(-3), null);
cek('posInt 2.5 ditolak',       Valid::posInt(2.5), null);
cek('posInt "abc" ditolak',     Valid::posInt('abc'), null);
cek('number "12.5"',            Valid::number('12.5'), 12.5);
cek('number "abc" ditolak',     Valid::number('abc'), null);

echo $gagal === 0 ? "\nSemua tes lulus\n" : "\n$gagal tes GAGAL\n";
exit($gagal === 0 ? 0 : 1);
