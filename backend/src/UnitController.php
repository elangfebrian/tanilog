<?php
declare(strict_types=1);

/** Kolam / kandang milik pengguna yang sedang login. */
class UnitController
{
    private const TIPE = ['kolam', 'kandang'];

    /** GET /unit */
    public function index(array $params = []): void
    {
        $user = Auth::user();
        $stmt = Database::pdo()->prepare(
            "SELECT u.id, u.nama, u.tipe, u.kapasitas, u.created_at,
                    (SELECT COUNT(*) FROM siklus s WHERE s.unit_id = u.id AND s.status = 'aktif') AS siklus_aktif
             FROM unit_budidaya u
             WHERE u.user_id = ?
             ORDER BY u.nama"
        );
        $stmt->execute([$user['sub']]);
        $data = array_map([$this, 'format'], $stmt->fetchAll());
        Response::json(['unit' => $data]);
    }

    /** POST /unit  {nama, tipe, kapasitas?} */
    public function store(array $params = []): void
    {
        $user = Auth::user();
        $in = $this->validate(Request::json());

        $pdo = Database::pdo();
        try {
            $stmt = $pdo->prepare(
                'INSERT INTO unit_budidaya (user_id, nama, tipe, kapasitas) VALUES (?, ?, ?, ?)'
            );
            $stmt->execute([$user['sub'], $in['nama'], $in['tipe'], $in['kapasitas']]);
        } catch (PDOException $e) {
            $this->duplicateOrRethrow($e);
        }
        $row = $this->find((int) $pdo->lastInsertId(), (int) $user['sub']);
        Response::json(['unit' => $this->format($row)], 201);
    }

    /** PUT /unit/{id}  {nama, tipe, kapasitas?} */
    public function update(array $params = []): void
    {
        $user = Auth::user();
        $id = Valid::idParam($params);
        $this->find($id, (int) $user['sub']);          // 404 bila bukan miliknya
        $in = $this->validate(Request::json());

        try {
            $stmt = Database::pdo()->prepare(
                'UPDATE unit_budidaya SET nama = ?, tipe = ?, kapasitas = ? WHERE id = ? AND user_id = ?'
            );
            $stmt->execute([$in['nama'], $in['tipe'], $in['kapasitas'], $id, $user['sub']]);
        } catch (PDOException $e) {
            $this->duplicateOrRethrow($e);
        }
        Response::json(['unit' => $this->format($this->find($id, (int) $user['sub']))]);
    }

    /** DELETE /unit/{id} : ditolak bila masih punya siklus (agar riwayat tidak hilang) */
    public function destroy(array $params = []): void
    {
        $user = Auth::user();
        $id = Valid::idParam($params);
        $this->find($id, (int) $user['sub']);

        $pdo = Database::pdo();
        $cek = $pdo->prepare('SELECT COUNT(*) FROM siklus WHERE unit_id = ?');
        $cek->execute([$id]);
        if ((int) $cek->fetchColumn() > 0) {
            Response::error('Unit masih memiliki siklus. Hapus siklusnya terlebih dahulu.', 409);
        }
        $pdo->prepare('DELETE FROM unit_budidaya WHERE id = ? AND user_id = ?')->execute([$id, $user['sub']]);
        Response::json(['message' => 'Unit dihapus']);
    }

    // ------------------------------------------------------------------

    private function validate(array $in): array
    {
        $nama = trim((string) ($in['nama'] ?? ''));
        $tipe = (string) ($in['tipe'] ?? '');
        $kapasitas = null;
        $errors = [];

        if ($nama === '' || mb_strlen($nama) > 60) {
            $errors['nama'] = 'Nama wajib diisi, maksimal 60 karakter';
        }
        if (!in_array($tipe, self::TIPE, true)) {
            $errors['tipe'] = "Tipe harus 'kolam' atau 'kandang'";
        }
        if (isset($in['kapasitas']) && $in['kapasitas'] !== '') {
            $kapasitas = Valid::posInt($in['kapasitas']);
            if ($kapasitas === null) {
                $errors['kapasitas'] = 'Kapasitas harus bilangan bulat positif';
            }
        }
        if ($errors) {
            Response::error('Data tidak valid', 422, $errors);
        }
        return ['nama' => $nama, 'tipe' => $tipe, 'kapasitas' => $kapasitas];
    }

    /** Baris unit milik pengguna, atau 404. */
    private function find(int $id, int $userId): array
    {
        $stmt = Database::pdo()->prepare(
            "SELECT u.id, u.nama, u.tipe, u.kapasitas, u.created_at,
                    (SELECT COUNT(*) FROM siklus s WHERE s.unit_id = u.id AND s.status = 'aktif') AS siklus_aktif
             FROM unit_budidaya u WHERE u.id = ? AND u.user_id = ?"
        );
        $stmt->execute([$id, $userId]);
        $row = $stmt->fetch();
        if (!$row) {
            Response::error('Unit tidak ditemukan', 404);
        }
        return $row;
    }

    private function format(array $r): array
    {
        return [
            'id'           => (int) $r['id'],
            'nama'         => $r['nama'],
            'tipe'         => $r['tipe'],
            'kapasitas'    => $r['kapasitas'] !== null ? (int) $r['kapasitas'] : null,
            'siklus_aktif' => (int) $r['siklus_aktif'],
            'created_at'   => $r['created_at'],
        ];
    }

    private function duplicateOrRethrow(PDOException $e): void
    {
        if ($e->getCode() === '23000') {
            Response::error('Nama unit sudah dipakai', 409);
        }
        throw $e;
    }
}
