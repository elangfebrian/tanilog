<?php
declare(strict_types=1);

/** JWT HS256 sederhana tanpa library tambahan (tidak perlu Composer). */
class Jwt
{
    public static function encode(array $payload, string $secret): string
    {
        $header = ['typ' => 'JWT', 'alg' => 'HS256'];
        $segments = [
            self::b64(json_encode($header)),
            self::b64(json_encode($payload)),
        ];
        $signature = hash_hmac('sha256', implode('.', $segments), $secret, true);
        $segments[] = self::b64($signature);
        return implode('.', $segments);
    }

    /** Mengembalikan payload bila tanda tangan valid dan belum kedaluwarsa, selain itu null. */
    public static function decode(string $token, string $secret): ?array
    {
        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            return null;
        }
        list($h, $p, $s) = $parts;

        $header = json_decode((string) self::unb64($h), true);
        if (!is_array($header) || ($header['alg'] ?? '') !== 'HS256') {
            return null;   // tolak algoritma lain (termasuk "none")
        }

        $expected = self::b64(hash_hmac('sha256', $h . '.' . $p, $secret, true));
        if (!hash_equals($expected, $s)) {
            return null;
        }

        $payload = json_decode((string) self::unb64($p), true);
        if (!is_array($payload)) {
            return null;
        }
        if (!isset($payload['exp']) || (int) $payload['exp'] < time()) {
            return null;
        }
        return $payload;
    }

    private static function b64(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    /** @return string|false */
    private static function unb64(string $data)
    {
        return base64_decode(strtr($data, '-_', '+/'), true);
    }
}
