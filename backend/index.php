<?php
declare(strict_types=1);

/**
 * Titik masuk REST API Tanilog.
 * Semua permintaan diarahkan ke sini oleh .htaccess, lalu dicocokkan di Router.
 */

require __DIR__ . '/src/Http.php';
require __DIR__ . '/src/Database.php';
require __DIR__ . '/src/Jwt.php';
require __DIR__ . '/src/Auth.php';
require __DIR__ . '/src/Router.php';
require __DIR__ . '/src/Helpers.php';
require __DIR__ . '/src/Milik.php';
require __DIR__ . '/src/CatatanController.php';
require __DIR__ . '/src/KeuanganController.php';
require __DIR__ . '/src/AuthController.php';
require __DIR__ . '/src/KomoditasController.php';
require __DIR__ . '/src/UnitController.php';
require __DIR__ . '/src/SiklusController.php';
require __DIR__ . '/src/LaporanController.php';

$configFile = __DIR__ . '/config.php';
if (!file_exists($configFile)) {
    Response::error('Salin config.example.php menjadi config.php lalu isi nilainya', 500);
}
$config = require $configFile;

// Zona waktu: agar "hari ini" sesuai jam setempat, bukan jam bawaan server
date_default_timezone_set((string) ($config['timezone'] ?? 'Asia/Jakarta'));

Response::configure((bool) $config['debug'], (string) $config['cors_origin']);
Response::cors();

// Semua error tak terduga dijawab sebagai JSON, bukan halaman HTML PHP
set_exception_handler(function (Throwable $e): void {
    $detail = Response::isDebug() ? ['message' => $e->getMessage()] : [];
    Response::error('Terjadi kesalahan pada server', 500, $detail);
});

Database::init($config['db']);
Auth::init((string) $config['jwt_secret'], (int) $config['jwt_ttl']);

$router = new Router();

// Cek cepat bahwa API dan database hidup
$router->add('GET', '/health', function (array $p): void {
    Database::pdo()->query('SELECT 1');
    Response::json(['status' => 'ok', 'app' => 'Tanilog API']);
});

$auth = new AuthController();
$router->add('POST', '/auth/register', [$auth, 'register']);
$router->add('POST', '/auth/login',    [$auth, 'login']);
$router->add('GET',  '/auth/me',       [$auth, 'me']);

$router->add('GET', '/komoditas', [new KomoditasController(), 'index']);

$router->add('GET', '/laporan/perbandingan', [new LaporanController(), 'perbandingan']);

$unit = new UnitController();
$router->add('GET',    '/unit',        [$unit, 'index']);
$router->add('POST',   '/unit',        [$unit, 'store']);
$router->add('PUT',    '/unit/{id}',   [$unit, 'update']);
$router->add('DELETE', '/unit/{id}',   [$unit, 'destroy']);

$siklus = new SiklusController();
$router->add('GET',    '/siklus',        [$siklus, 'index']);
$router->add('POST',   '/siklus',        [$siklus, 'store']);
$router->add('GET',    '/siklus/{id}',   [$siklus, 'show']);
$router->add('GET',    '/siklus/{id}/grafik', [$siklus, 'grafik']);
$router->add('PUT',    '/siklus/{id}',   [$siklus, 'update']);
$router->add('DELETE', '/siklus/{id}',   [$siklus, 'destroy']);

// Catatan harian: pakan, kematian, sampling. Pola rute sama, hanya nama jenisnya yang berbeda.
$catatan = new CatatanController();
foreach (['pakan', 'kematian', 'sampling'] as $jenis) {
    $router->add('GET',    '/siklus/{id}/' . $jenis, function (array $p) use ($catatan, $jenis): void { $catatan->index($jenis, $p); });
    $router->add('POST',   '/siklus/{id}/' . $jenis, function (array $p) use ($catatan, $jenis): void { $catatan->store($jenis, $p); });
    $router->add('PUT',    '/siklus/{id}/' . $jenis . '/{cid}', function (array $p) use ($catatan, $jenis): void { $catatan->update($jenis, $p); });
    $router->add('DELETE', '/siklus/{id}/' . $jenis . '/{cid}', function (array $p) use ($catatan, $jenis): void { $catatan->destroy($jenis, $p); });
}

// Keuangan dan panen
$keu = new KeuanganController();
$router->add('GET',    '/siklus/{id}/transaksi',         [$keu, 'transaksiIndex']);
$router->add('POST',   '/siklus/{id}/transaksi',         [$keu, 'transaksiStore']);
$router->add('DELETE', '/siklus/{id}/transaksi/{tid}',   [$keu, 'transaksiDestroy']);
$router->add('GET',    '/siklus/{id}/panen',             [$keu, 'panenShow']);
$router->add('POST',   '/siklus/{id}/panen',             [$keu, 'panenStore']);
$router->add('DELETE', '/siklus/{id}/panen',             [$keu, 'panenDestroy']);

// Endpoint berikutnya (jadwal pakan, admin) ditambahkan di sini.

$router->dispatch($_SERVER['REQUEST_METHOD'] ?? 'GET', $_SERVER['REQUEST_URI'] ?? '/');
