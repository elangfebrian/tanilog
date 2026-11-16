# Dokumentasi API Tanilog

Alamat dasar (XAMPP, folder repo di `htdocs`):
`http://localhost/tanilog-repo/backend`

Semua permintaan dan respons berformat JSON. Kirim header `Content-Type: application/json`.
Endpoint yang butuh login memakai header `Authorization: Bearer <token>`.

## Format error
```json
{ "error": "Pesan singkat", "details": { "field": "penjelasan" } }
```
`details` hanya muncul bila ada rincian (misalnya validasi form).

| Kode | Arti |
|------|------|
| 400 | Body bukan JSON yang valid |
| 401 | Belum login / token salah / kedaluwarsa |
| 403 | Login, tetapi peran tidak berhak |
| 404 | Endpoint atau data tidak ada |
| 405 | Metode HTTP salah |
| 409 | Data bentrok (misalnya email sudah terdaftar) |
| 422 | Data tidak lolos validasi |
| 500 | Kesalahan server |

## Endpoint

### GET /health
Cek API dan koneksi database. Respons 200: `{"status":"ok","app":"Tanilog API"}`

### POST /auth/register
Body:
```json
{ "nama": "Budi Santoso", "email": "budi@contoh.com", "password": "minimal8kar", "no_hp": "081234567890" }
```
`no_hp` opsional. Peran akun baru selalu `peternak`.

Respons 201:
```json
{ "user": { "id": 3, "nama": "Budi Santoso", "email": "budi@contoh.com", "no_hp": "081234567890", "role": "peternak" },
  "token": "eyJ..." }
```
Error: 409 (email terdaftar), 422 (data tidak valid).

### POST /auth/login
Body: `{ "email": "budi@tanilog.test", "password": "peternak123" }`

Respons 200: bentuk sama seperti register (`user` + `token`).
Error: 401 (email atau kata sandi salah), 422 (kosong).

### GET /auth/me  (butuh login)
Respons 200: `{ "user": { "id", "nama", "email", "no_hp", "role", "created_at" } }`

## Mencoba di Postman
1. `POST /auth/login` dengan akun contoh, salin nilai `token` dari respons.
2. Buka tab **Authorization**, pilih **Bearer Token**, tempel token.
3. Kirim `GET /auth/me`. Bila muncul data akun, autentikasi berjalan.

Akun contoh (dari `database/schema.sql`, hanya untuk pengembangan):
- `admin@tanilog.test` / `admin123`
- `budi@tanilog.test` / `peternak123`

### GET /komoditas  (butuh login)
Daftar komoditas aktif untuk pilihan di form siklus.
```json
{ "komoditas": [ { "id": 1, "nama": "Lele", "jenis": "ikan", "durasi_panen_hari": 60,
  "target_bobot_panen_g": 250, "fcr_standar_maks": 1.3, "sr_standar_min": 85 } ] }
```

## Unit budidaya (kolam / kandang)
Semua endpoint butuh login dan hanya menyentuh unit milik pengguna sendiri
(unit milik orang lain dijawab 404).

| Metode | Alamat | Fungsi |
|--------|--------|--------|
| GET | `/unit` | Daftar unit, urut nama, beserta `siklus_aktif` |
| POST | `/unit` | Buat unit |
| PUT | `/unit/{id}` | Ubah unit |
| DELETE | `/unit/{id}` | Hapus unit (409 bila masih punya siklus) |

Body POST/PUT: `{ "nama": "Kolam A1", "tipe": "kolam", "kapasitas": 2500 }`
`tipe` hanya `kolam` atau `kandang`; `kapasitas` opsional. Nama unit harus unik per pengguna (409 bila kembar).

## Siklus budidaya
Semua endpoint butuh login dan hanya menyentuh siklus milik pengguna sendiri.

| Metode | Alamat | Fungsi |
|--------|--------|--------|
| GET | `/siklus` | Daftar siklus + ringkasan. Filter opsional `?status=aktif\|selesai\|gagal` |
| POST | `/siklus` | Buat siklus baru |
| GET | `/siklus/{id}` | Detail: data siklus, ringkasan hitungan, keuangan |
| PUT | `/siklus/{id}` | Ubah sebagian field (kirim hanya yang diubah) |
| DELETE | `/siklus/{id}` | Hapus siklus beserta seluruh catatannya |

**POST /siklus**
```json
{ "unit_id": 1, "komoditas_id": 1, "tanggal_mulai": "2026-11-14", "populasi_awal": 2000, "bobot_awal_g": 5, "catatan": "Bibit dari BBI" }
```
`bobot_awal_g` dan `catatan` opsional. `siklus_ke` dihitung otomatis per unit.
Satu unit hanya boleh punya satu siklus `aktif` (409 bila sudah ada).

**PUT /siklus/{id}** menerima: `tanggal_mulai`, `populasi_awal`, `bobot_awal_g`, `catatan`,
`status` (`aktif`/`selesai`/`gagal`), `tanggal_selesai`.
Mengubah status ke `selesai`/`gagal` mengisi `tanggal_selesai` dengan hari ini bila tidak dikirim.
`populasi_awal` tidak boleh lebih kecil dari total kematian yang sudah dicatat.

**Respons GET /siklus/{id}** (ringkas)
```json
{
  "siklus":   { "id": 2, "siklus_ke": 4, "unit_nama": "Kolam A1", "komoditas": "Lele", "status": "aktif",
                "tanggal_mulai": "2026-09-22", "populasi_awal": 2000, "bobot_awal_g": 5 },
  "ringkasan": {
    "umur_hari": 53, "populasi_hidup": 1876, "total_mati": 124,
    "sr_persen": 93.8, "sr_status": "baik",
    "total_pakan_kg": 253, "bobot_terakhir_g": 128, "biomassa_kini_kg": 240.13,
    "fcr": 1.1, "fcr_status": "baik",
    "estimasi_panen": { "tanggal": "2026-11-23", "sisa_hari": 9, "metode": "kurva_standar", "umur_setara": 42 }
  },
  "keuangan": { "total_modal": 3394000, "total_pendapatan": 0, "laba_rugi": -3394000 }
}
```

### Cara perhitungan
- **SR** = populasi hidup / populasi awal x 100. `sr_status` = `baik` bila SR >= `sr_standar_min` komoditas.
- **FCR** = total pakan (kg) / pertambahan biomassa (kg); biomassa = populasi hidup x bobot rata-rata / 1000.
  `null` bila belum ada sampling bobot. `fcr_status` = `baik` bila FCR <= `fcr_standar_maks`.
- **Estimasi panen** (hanya siklus `aktif`):
  - Bila sudah ada sampling: cari pada hari ke berapa bobot standar sama dengan bobot aktual terakhir
    (interpolasi linear pada tabel `standar_pertumbuhan`), disebut *umur setara*. Sisa hari =
    durasi panen standar - umur setara, dihitung dari tanggal sampling terakhir. `metode`: `kurva_standar`.
  - Bila belum ada sampling: tanggal mulai + durasi panen standar. `metode`: `umur_standar`.
  - `sisa_hari` negatif berarti sudah melewati perkiraan.

### GET /siklus/{id}/grafik
Data grafik pertumbuhan: kurva standar komoditas dan bobot nyata hasil sampling.
`hari` = selisih tanggal dengan `tanggal_mulai`. Titik hari 0 (`bobot_awal_g`) ikut bila terisi.
```json
{ "durasi_panen_hari": 60, "target_bobot_panen_g": 250,
  "standar": [ { "hari": 0, "bobot_g": 5 }, { "hari": 10, "bobot_g": 15 } ],
  "aktual":  [ { "hari": 0, "tanggal": "2026-09-22", "bobot_g": 5 }, { "hari": 44, "tanggal": "2026-11-05", "bobot_g": 128 } ] }
```

## Catatan harian: pakan, kematian, sampling bobot
Ketiganya berpola sama; `{jenis}` adalah `pakan`, `kematian`, atau `sampling`.
Semua butuh login dan hanya untuk siklus milik pengguna sendiri.

| Metode | Alamat | Fungsi |
|--------|--------|--------|
| GET | `/siklus/{id}/{jenis}` | Daftar catatan (terbaru dulu) + total |
| POST | `/siklus/{id}/{jenis}` | Tambah catatan (hanya siklus `aktif`, selain itu 409) |
| PUT | `/siklus/{id}/{jenis}/{cid}` | Ubah catatan (kirim ulang seluruh isian) |
| DELETE | `/siklus/{id}/{jenis}/{cid}` | Hapus catatan |

Body:
- **pakan:** `{ "jumlah_kg": 12.5, "waktu": "2026-11-14 17:00", "catatan": "opsional" }`.
  `waktu` bila kosong = sekarang.
- **kematian:** `{ "jumlah": 3, "tanggal": "2026-11-14", "penyebab": "opsional" }`.
  Total kematian tidak boleh melebihi populasi awal.
- **sampling:** `{ "bobot_rata_g": 128, "jumlah_sampel": 20, "tanggal": "2026-11-14" }`.
  `jumlah_sampel` bila kosong = 1.

`tanggal` bila kosong = hari ini. Tanggal tidak boleh sebelum tanggal mulai siklus dan tidak boleh
lebih dari besok (422).

Respons POST, PUT, dan DELETE menyertakan `ringkasan` terbaru agar layar bisa langsung menampilkan
angka setelah menyimpan:
```json
{ "catatan": { "id": 7, "waktu": "2026-11-14 17:00:00", "jumlah_kg": 12.5, "catatan": null },
  "ringkasan": { "populasi_hidup": 1876, "total_mati": 124, "sr_persen": 93.8,
                 "total_pakan_kg": 265.5, "bobot_terakhir_g": 128, "fcr": 1.15 } }
```

## Keuangan dan panen

| Metode | Alamat | Fungsi |
|--------|--------|--------|
| GET | `/siklus/{id}/transaksi` | Daftar transaksi + rincian per kategori + laba rugi |
| POST | `/siklus/{id}/transaksi` | Tambah modal atau pendapatan |
| DELETE | `/siklus/{id}/transaksi/{tid}` | Hapus transaksi |
| GET | `/siklus/{id}/panen` | Data panen (404 bila belum panen) |
| POST | `/siklus/{id}/panen` | Catat panen |
| DELETE | `/siklus/{id}/panen` | Batalkan panen |

**POST /siklus/{id}/transaksi**
```json
{ "tipe": "modal", "kategori": "pakan", "tanggal": "2026-11-14", "keterangan": "Pelet 25 kg", "jumlah_rp": 300000 }
```
- `tipe` `modal`: kategori `bibit`, `pakan`, `obat`, `tenaga`, `listrik`, atau `lainnya`.
- `tipe` `pendapatan`: kategori hanya `penjualan`.
- Transaksi yang dibuat otomatis dari panen (`dari_panen: true`) tidak bisa dihapus langsung (409);
  batalkan lewat `DELETE /siklus/{id}/panen`.

**POST /siklus/{id}/panen**
```json
{ "tanggal": "2026-11-23", "jumlah_ekor": 1800, "bobot_total_kg": 430, "harga_per_kg": 22000 }
```
Satu panen per siklus. Dalam satu transaksi database, server: (1) menyimpan panen, (2) membuat
pendapatan `penjualan` sebesar bobot x harga, (3) mengubah siklus menjadi `selesai`.
`jumlah_ekor` tidak boleh melebihi populasi hidup (422).
`DELETE` membatalkan semuanya: pendapatan terhapus dan siklus kembali `aktif`
(ditolak 409 bila unit sudah punya siklus aktif lain).

Respons berisi `panen` (termasuk `bobot_rata_g` dan `total_rp`) dan `keuangan`
(`total_modal`, `total_pendapatan`, `laba_rugi`). Rumus: laba rugi = total pendapatan - total modal.

## Admin
Hanya peran `admin` (peran dicek ulang ke database). Peternak mendapat 403. Akun admin dibuat manual di database.

| Metode | Alamat | Fungsi |
|--------|--------|--------|
| GET | `/admin/ringkasan` | Jumlah peternak, unit, siklus aktif, siklus selesai, komoditas aktif |
| GET | `/admin/komoditas` | Semua komoditas (termasuk nonaktif) + `jumlah_siklus`, `jumlah_titik` |
| POST | `/admin/komoditas` | Tambah komoditas |
| PUT | `/admin/komoditas/{id}` | Ubah komoditas (kirim seluruh isian, `aktif` boleh false) |
| GET | `/admin/komoditas/{id}/standar` | Kurva standar pertumbuhan |
| PUT | `/admin/komoditas/{id}/standar` | Ganti seluruh kurva dalam satu transaksi |

Body komoditas: `{ "nama", "jenis": "ikan|unggas", "durasi_panen_hari", "target_bobot_panen_g", "fcr_standar_maks", "sr_standar_min", "aktif" }`.
Nama harus unik (409). Komoditas nonaktif tidak muncul di `GET /komoditas` (pilihan siklus baru),
tetapi siklus yang sudah berjalan tetap memakainya.

Body kurva: `{ "standar": [ { "hari_ke": 0, "bobot_standar_g": 5 }, { "hari_ke": 60, "bobot_standar_g": 250 } ] }`.
Minimal 2 titik, hari tidak boleh kembar, dan bobot tidak boleh turun seiring hari (422), sebab estimasi
panen mencari umur setara lewat interpolasi pada kurva ini. Bila ada kesalahan, kurva lama tidak berubah.

## Jadwal pakan dan pengingat
| Metode | Alamat | Fungsi |
|--------|--------|--------|
| GET | `/siklus/{id}/jadwal-pakan` | Daftar jadwal (urut jam) |
| POST | `/siklus/{id}/jadwal-pakan` | Tambah `{ "jam": "07:00", "jumlah_kg": 12.5 }` |
| PUT | `/siklus/{id}/jadwal-pakan/{jid}` | Ubah `{ "jam", "jumlah_kg", "aktif"? }` |
| DELETE | `/siklus/{id}/jadwal-pakan/{jid}` | Hapus jadwal |
| GET | `/pengingat/hari-ini` | Jadwal aktif semua siklus aktif beserta status hari ini |

`jam` berformat `HH:MM` 24 jam. **Status** tiap jadwal pada `/pengingat/hari-ini`:
catatan pakan hari ini dicocokkan berurutan dengan jadwal (N catatan = N jadwal paling awal `sudah`).
Sisanya: `waktunya` bila jam server sudah lewat jadwal sampai 30 menit, `terlambat` bila lebih dari itu,
`menunggu` bila belum tiba. `belum_total` = jumlah jadwal yang belum `sudah`.
```json
{ "tanggal": "2026-11-17", "jam_server": "10:15", "belum_total": 2,
  "pengingat": [ { "siklus_id": 2, "label": "Kolam A1 · Siklus 4", "komoditas": "Lele",
    "jadwal": [ { "jadwal_id": 1, "jam": "07:00", "jumlah_kg": 12.5, "status": "sudah" },
                { "jadwal_id": 2, "jam": "12:00", "jumlah_kg": 12.5, "status": "menunggu" } ] } ] }
```

## Laporan
### GET /laporan/perbandingan  (butuh login)
Satu baris per siklus milik pengguna (terlama dulu) untuk dibandingkan. Filter opsional `?komoditas_id=`.
`ringkasan` dihitung hanya dari siklus berstatus `selesai`.
```json
{ "siklus": [ { "id": 1, "label": "Kolam A1 · Siklus 3", "komoditas": "Lele", "status": "selesai",
                "umur_hari": 60, "sr_persen": 92.5, "fcr": 1.18, "fcr_standar_maks": 1.3, "sr_standar_min": 85,
                "total_modal": 7120000, "total_pendapatan": 9450000, "laba_rugi": 2330000 } ],
  "ringkasan": { "jumlah_selesai": 1, "rata_sr_persen": 92.5, "rata_fcr": 1.18,
                 "total_laba_rugi": 2330000, "terbaik": { "id": 1, "label": "Kolam A1 · Siklus 3", "laba_rugi": 2330000 } } }
```

## Pengujian
- `php backend/tests/HitungTest.php` menguji perhitungan estimasi panen dan validasi (tanpa database).
- Seluruh endpoint di dokumen ini diuji lewat HTTP terhadap MySQL/MariaDB, termasuk
  pemisahan data antar pengguna (data milik pengguna lain selalu dijawab 404).

## Rencana endpoint berikutnya
(belum ada).
