<?php
declare(strict_types=1);

class AuthController
{
    /** POST /auth/register  {nama, email, password, no_hp?} */
    public function register(array $params = []): void
    {
        $in = Request::json();
        $nama = trim((string) ($in['nama'] ?? ''));
        $email = strtolower(trim((string) ($in['email'] ?? '')));
        $password = (string) ($in['password'] ?? '');
        $noHp = trim((string) ($in['no_hp'] ?? ''));

        $errors = [];
        if (mb_strlen($nama) < 2 || mb_strlen($nama) > 100) {
            $errors['nama'] = 'Nama 2-100 karakter';
        }
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 120) {
            $errors['email'] = 'Format email tidak valid';
        }
        if (strlen($password) < 8) {
            $errors['password'] = 'Kata sandi minimal 8 karakter';
        }
        if ($noHp !== '' && !preg_match('/^[0-9+\- ]{6,20}$/', $noHp)) {
            $errors['no_hp'] = 'Nomor HP tidak valid';
        }
        if ($errors) {
            Response::error('Data tidak valid', 422, $errors);
        }

        $pdo = Database::pdo();
        $cek = $pdo->prepare('SELECT id FROM users WHERE email = ?');
        $cek->execute([$email]);
        if ($cek->fetch()) {
            Response::error('Email sudah terdaftar', 409);
        }

        // Peran selalu 'peternak'. Admin dibuat manual lewat database, bukan lewat API.
        $stmt = $pdo->prepare(
            'INSERT INTO users (nama, email, password_hash, no_hp, role) VALUES (?, ?, ?, ?, ?)'
        );
        try {
            $stmt->execute([
                $nama,
                $email,
                password_hash($password, PASSWORD_DEFAULT),
                $noHp !== '' ? $noHp : null,
                'peternak',
            ]);
        } catch (PDOException $e) {
            if ($e->getCode() === '23000') {   // pelanggaran UNIQUE: email dipakai bersamaan
                Response::error('Email sudah terdaftar', 409);
            }
            throw $e;
        }

        $user = [
            'id'    => (int) $pdo->lastInsertId(),
            'nama'  => $nama,
            'email' => $email,
            'no_hp' => $noHp !== '' ? $noHp : null,
            'role'  => 'peternak',
        ];
        Response::json(['user' => $user, 'token' => Auth::issueToken($user)], 201);
    }

    /** POST /auth/login  {email, password} */
    public function login(array $params = []): void
    {
        $in = Request::json();
        $email = strtolower(trim((string) ($in['email'] ?? '')));
        $password = (string) ($in['password'] ?? '');

        if ($email === '' || $password === '') {
            Response::error('Email dan kata sandi wajib diisi', 422);
        }

        $stmt = Database::pdo()->prepare(
            'SELECT id, nama, email, no_hp, role, password_hash FROM users WHERE email = ?'
        );
        $stmt->execute([$email]);
        $row = $stmt->fetch();

        // Pesan sama untuk "email tidak ada" dan "sandi salah" agar akun tidak bisa ditebak
        if (!$row || !password_verify($password, $row['password_hash'])) {
            Response::error('Email atau kata sandi salah', 401);
        }

        unset($row['password_hash']);
        Response::json(['user' => $row, 'token' => Auth::issueToken($row)]);
    }

    /** GET /auth/me  (butuh header Authorization: Bearer <token>) */
    public function me(array $params = []): void
    {
        $payload = Auth::user();
        $stmt = Database::pdo()->prepare(
            'SELECT id, nama, email, no_hp, role, created_at FROM users WHERE id = ?'
        );
        $stmt->execute([$payload['sub']]);
        $user = $stmt->fetch();
        if (!$user) {
            Response::error('Akun tidak ditemukan', 404);
        }
        Response::json(['user' => $user]);
    }
}
