<?php
declare(strict_types=1);

/** Pemeriksaan input yang dipakai berulang oleh controller. */
class Valid
{
    /** Tanggal format YYYY-MM-DD yang benar-benar ada di kalender. */
    public static function date($s): bool
    {
        if (!is_string($s)) {
            return false;
        }
        $d = DateTime::createFromFormat('Y-m-d', $s);
        return $d !== false && $d->format('Y-m-d') === $s;
    }

    /** Waktu 'YYYY-MM-DD HH:MM[:SS]' (pemisah 'T' boleh); dinormalkan ke 'Y-m-d H:i:s', atau null. */
    public static function datetime($s): ?string
    {
        if (!is_string($s)) {
            return null;
        }
        foreach (['Y-m-d H:i:s', 'Y-m-d H:i', 'Y-m-d\TH:i:s', 'Y-m-d\TH:i'] as $format) {
            $d = DateTime::createFromFormat($format, $s);
            if ($d !== false && $d->format($format) === $s) {
                return $d->format('Y-m-d H:i:s');
            }
        }
        return null;
    }

    /** Bilangan bulat positif dari JSON (5, "5", 5.0), selain itu null. */
    public static function posInt($v): ?int
    {
        if (is_int($v)) {
            return $v > 0 ? $v : null;
        }
        if (is_float($v) && floor($v) === $v && $v > 0) {
            return (int) $v;
        }
        if (is_string($v) && ctype_digit($v) && (int) $v > 0) {
            return (int) $v;
        }
        return null;
    }

    /** Angka (boleh desimal) dari JSON, selain itu null. */
    public static function number($v): ?float
    {
        if (is_int($v) || is_float($v)) {
            return (float) $v;
        }
        if (is_string($v) && is_numeric($v)) {
            return (float) $v;
        }
        return null;
    }

    /** Ambil {id} dari URL; 404 bila bukan angka positif. */
    public static function idParam(array $params, string $key = 'id'): int
    {
        $v = (string) ($params[$key] ?? '');
        if (!ctype_digit($v) || (int) $v < 1) {
            Response::error('Data tidak ditemukan', 404);
        }
        return (int) $v;
    }
}

/**
 * Perhitungan budidaya yang tidak bergantung pada database,
 * sehingga mudah diuji sendiri (lihat backend/tests/HitungTest.php).
 */
class Hitung
{
    /**
     * Umur "setara" pada kurva standar: pada hari ke berapa bobot standar
     * sama dengan bobot aktual. Antar dua titik standar dihitung linear.
     *
     * @param array $standar  [['hari_ke'=>0,'bobot_standar_g'=>5], ...] terurut menurut hari_ke
     */
    public static function hariSetara(float $bobot, array $standar): ?float
    {
        if (!$standar) {
            return null;
        }
        $first = $standar[0];
        $last = $standar[count($standar) - 1];
        if ($bobot <= (float) $first['bobot_standar_g']) {
            return (float) $first['hari_ke'];
        }
        if ($bobot >= (float) $last['bobot_standar_g']) {
            return (float) $last['hari_ke'];
        }
        for ($i = 1; $i < count($standar); $i++) {
            $h1 = (float) $standar[$i - 1]['hari_ke'];
            $b1 = (float) $standar[$i - 1]['bobot_standar_g'];
            $h2 = (float) $standar[$i]['hari_ke'];
            $b2 = (float) $standar[$i]['bobot_standar_g'];
            if ($bobot >= $b1 && $bobot <= $b2) {
                if ($b2 == $b1) {
                    return $h1;
                }
                return $h1 + ($bobot - $b1) / ($b2 - $b1) * ($h2 - $h1);
            }
        }
        return (float) $last['hari_ke'];
    }

    /**
     * Perkiraan tanggal panen.
     * Dengan sampling: cari umur setara di kurva standar, sisa hari = durasi panen - umur setara,
     * dihitung dari tanggal sampling terakhir. Tanpa sampling: tanggal mulai + durasi standar.
     *
     * @return array ['tanggal'=>'YYYY-MM-DD','sisa_hari'=>int,'metode'=>string,'umur_setara'=>?float]
     *               sisa_hari dihitung dari $hariIni; negatif berarti sudah lewat perkiraan.
     */
    public static function estimasiPanen(
        string $tanggalMulai,
        int $durasiPanen,
        ?float $bobotTerakhir,
        ?string $tanggalBobot,
        array $standar,
        string $hariIni
    ): array {
        $umurSetara = null;
        if ($bobotTerakhir !== null && $tanggalBobot !== null && $standar) {
            $umurSetara = self::hariSetara($bobotTerakhir, $standar);
        }

        if ($umurSetara === null) {
            $target = new DateTime($tanggalMulai);
            $target->modify('+' . $durasiPanen . ' days');
            $metode = 'umur_standar';
        } else {
            $sisa = max(0, (int) ceil($durasiPanen - $umurSetara));
            $target = new DateTime((string) $tanggalBobot);
            $target->modify('+' . $sisa . ' days');
            $metode = 'kurva_standar';
        }

        $today = new DateTime($hariIni);
        $selisih = (int) $today->diff($target)->format('%r%a');

        return [
            'tanggal'     => $target->format('Y-m-d'),
            'sisa_hari'   => $selisih,
            'metode'      => $metode,
            'umur_setara' => $umurSetara !== null ? round($umurSetara, 1) : null,
        ];
    }
}
