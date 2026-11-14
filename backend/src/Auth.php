<?php
declare(strict_types=1);

/** Pembuatan token dan penjagaan endpoint yang butuh login. */
class Auth
{
    private static string $secret = '';
    private static int $ttl = 604800;

    public static function init(string $secret, int $ttl): void
    {
        if (strlen($secret) < 32 || strpos($secret, 'GANTI_DENGAN') === 0) {
            throw new RuntimeException('jwt_secret di config.php belum diisi (minimal 32 karakter)');
        }
        self::$secret = $secret;
        self::$ttl = $ttl;
    }

    public static function issueToken(array $user): string
    {
        $now = time();
        return Jwt::encode([
            'sub'  => (int) $user['id'],
            'role' => $user['role'],
            'iat'  => $now,
            'exp'  => $now + self::$ttl,
        ], self::$secret);
    }

    private static function bearerToken(): ?string
    {
        $header = $_SERVER['HTTP_AUTHORIZATION']
            ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
            ?? null;

        if ($header === null && function_exists('getallheaders')) {
            foreach (getallheaders() as $name => $value) {
                if (strcasecmp($name, 'Authorization') === 0) {
                    $header = $value;
                    break;
                }
            }
        }
        if ($header !== null && preg_match('/^Bearer\s+(\S+)$/i', $header, $m)) {
            return $m[1];
        }
        return null;
    }

    /** Payload token milik pengguna yang sedang login; 401 bila tidak valid. */
    public static function user(): array
    {
        $token = self::bearerToken();
        $payload = $token ? Jwt::decode($token, self::$secret) : null;
        if ($payload === null) {
            Response::error('Belum login atau token tidak valid', 401);
        }
        return $payload;
    }

    /** Sama seperti user(), tetapi 403 bila peran tidak sesuai (misalnya 'admin'). */
    public static function requireRole(string $role): array
    {
        $user = self::user();
        if (($user['role'] ?? '') !== $role) {
            Response::error('Anda tidak berhak mengakses ini', 403);
        }
        return $user;
    }
}
