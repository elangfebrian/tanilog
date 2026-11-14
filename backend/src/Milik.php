<?php
declare(strict_types=1);

/** Pemeriksaan kepemilikan data: pengguna hanya boleh menyentuh miliknya sendiri. */
class Milik
{
    /** Baris siklus milik pengguna, atau 404 (juga bila siklus milik orang lain). */
    public static function siklus(int $id, int $userId): array
    {
        $stmt = Database::pdo()->prepare('SELECT * FROM siklus WHERE id = ? AND user_id = ?');
        $stmt->execute([$id, $userId]);
        $row = $stmt->fetch();
        if (!$row) {
            Response::error('Siklus tidak ditemukan', 404);
        }
        return $row;
    }
}
