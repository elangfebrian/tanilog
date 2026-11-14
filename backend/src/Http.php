<?php
declare(strict_types=1);

/** Pembantu untuk membaca permintaan dan menulis respons JSON. */
class Response
{
    private static bool $debug = false;
    private static string $corsOrigin = '*';

    public static function configure(bool $debug, string $corsOrigin): void
    {
        self::$debug = $debug;
        self::$corsOrigin = $corsOrigin;
    }

    public static function isDebug(): bool
    {
        return self::$debug;
    }

    /** Header CORS agar bisa dipanggil dari Flutter web / alat lain saat pengembangan. */
    public static function cors(): void
    {
        header('Access-Control-Allow-Origin: ' . self::$corsOrigin);
        header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS');
        header('Access-Control-Allow-Headers: Content-Type, Authorization');
        header('Access-Control-Max-Age: 86400');
        if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
            http_response_code(204);
            exit;
        }
    }

    /** @param mixed $data */
    public static function json($data, int $status = 200): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    /** Bentuk error seragam: {"error": "...", "details": {...}} */
    public static function error(string $message, int $status = 400, array $details = []): void
    {
        $payload = ['error' => $message];
        if ($details) {
            $payload['details'] = $details;
        }
        self::json($payload, $status);
    }
}

class Request
{
    /** Isi body JSON sebagai array. Body kosong menghasilkan array kosong. */
    public static function json(): array
    {
        $raw = file_get_contents('php://input');
        if ($raw === false || trim($raw) === '') {
            return [];
        }
        $data = json_decode($raw, true);
        if (!is_array($data)) {
            Response::error('Body harus berupa JSON yang valid', 400);
        }
        return $data;
    }
}
