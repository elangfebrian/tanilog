<?php
declare(strict_types=1);

/** Satu koneksi PDO yang dipakai bersama oleh seluruh endpoint. */
class Database
{
    private static ?PDO $pdo = null;
    private static array $cfg = [];

    public static function init(array $dbConfig): void
    {
        self::$cfg = $dbConfig;
    }

    public static function pdo(): PDO
    {
        if (self::$pdo === null) {
            $c = self::$cfg;
            $dsn = sprintf(
                'mysql:host=%s;port=%d;dbname=%s;charset=%s',
                $c['host'], $c['port'], $c['name'], $c['charset']
            );
            self::$pdo = new PDO($dsn, $c['user'], $c['pass'], [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,   // prepared statement asli (anti SQL injection)
            ]);
        }
        return self::$pdo;
    }
}
