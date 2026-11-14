<?php
/**
 * Contoh konfigurasi. Salin file ini menjadi config.php lalu isi nilainya.
 * config.php TIDAK ikut Git (lihat .gitignore), jadi aman untuk kata sandi.
 *
 * Membuat jwt_secret acak (jalankan di PowerShell):
 *   php -r "echo bin2hex(random_bytes(32));"
 */
return [
    'db' => [
        'host'    => '127.0.0.1',
        'port'    => 3306,
        'name'    => 'tanilog',
        'user'    => 'root',
        'pass'    => '',            // XAMPP bawaan: kosong
        'charset' => 'utf8mb4',
    ],
    'jwt_secret' => 'GANTI_DENGAN_HASIL_PERINTAH_DI_ATAS_MINIMAL_32_KARAKTER',
    'jwt_ttl'    => 60 * 60 * 24 * 7,   // masa berlaku token: 7 hari
    'cors_origin' => '*',               // saat pengembangan; batasi bila di-hosting
    'debug'      => true,               // tampilkan pesan error rinci (matikan di hosting)
];
