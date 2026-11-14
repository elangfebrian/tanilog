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
require __DIR__ . '/src/AuthController.php';
require __DIR__ . '/src/KomoditasController.php';
require __DIR__ . '/src/UnitController.php';
require __DIR__ . '/src/SiklusController.php';

$configFile = __DIR__ . '/config.php';
if (!file_exists($configFile)) {
    Response::error('Salin config.example.php menjadi config.php lalu isi nilainya', 500);
}
$config = require $configFile;

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

$unit = new UnitController();
$router->add('GET',    '/unit',        [$unit, 'index']);
$router->add('POST',   '/unit',        [$unit, 'store']);
$router->add('PUT',    '/unit/{id}',   [$unit, 'update']);
$router->add('DELETE', '/unit/{id}',   [$unit, 'destroy']);

$siklus = new SiklusController();
$router->add('GET',    '/siklus',        [$siklus, 'index']);
$router->add('POST',   '/siklus',        [$siklus, 'store']);
$router->add('GET',    '/siklus/{id}',   [$siklus, 'show']);
$router->add('PUT',    '/siklus/{id}',   [$siklus, 'update']);
$router->add('DELETE', '/siklus/{id}',   [$siklus, 'destroy']);

// Endpoint berikutnya (catatan pakan, kematian, sampling, transaksi, panen, admin) ditambahkan di sini.

$router->dispatch($_SERVER['REQUEST_METHOD'] ?? 'GET', $_SERVER['REQUEST_URI'] ?? '/');
