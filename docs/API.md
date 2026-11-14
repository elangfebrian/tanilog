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

## Rencana endpoint berikutnya
`/siklus/{id}/pakan`, `/siklus/{id}/kematian`, `/siklus/{id}/sampling`, `/siklus/{id}/transaksi`,
`/siklus/{id}/panen`, `/siklus/{id}/jadwal-pakan`, `/admin/komoditas`, `/admin/standar`.
