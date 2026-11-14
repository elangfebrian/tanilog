# Tanilog

Aplikasi pencatat dan analisis budidaya ternak dan ikan skala kecil berbasis Flutter.

Membantu peternak skala kecil mengelola budidaya **lele, ayam pedaging, dan bebek**:
mencatat pakan, kematian, dan bobot sampling; menghitung perkiraan panen, FCR, dan
tingkat kelangsungan hidup (SR); serta mencatat modal dan pendapatan untuk melihat
laba atau rugi tiap siklus.

## Teknologi
| Bagian   | Teknologi                    |
|----------|------------------------------|
| Frontend | Flutter (Android)            |
| Backend  | PHP (REST API)               |
| Database | MySQL / MariaDB (XAMPP)      |

## Struktur repo
```
mobile/     Aplikasi Flutter
backend/    REST API PHP
database/   Skema dan data awal SQL
docs/       Desain layar, ERD, catatan untuk artikel
```

## Fitur
- [ ] Login dan registrasi (peternak, admin)
- [ ] Kelola kolam dan kandang
- [ ] Buat siklus budidaya per kolam atau kandang
- [ ] Catat pakan, kematian, dan bobot sampling
- [ ] Hitung SR, FCR, dan perkiraan waktu panen
- [ ] Pengingat jadwal pakan
- [ ] Catat modal dan pendapatan, tampilkan laba rugi
- [ ] Grafik pertumbuhan (aktual vs standar)
- [ ] Perbandingan antar siklus
- [ ] Admin: kelola komoditas dan standar pertumbuhan

## Menjalankan database
1. Jalankan Apache dan MySQL di XAMPP.
2. Buka phpMyAdmin, pilih tab **Import**, pilih `database/schema.sql`.
3. Database `tanilog` terbentuk lengkap dengan data contoh.

Akun contoh (hanya untuk pengembangan):
- Admin: `admin@tanilog.test` / `admin123`
- Peternak: `budi@tanilog.test` / `peternak123`

## Rumus
- **SR** = populasi hidup / populasi awal x 100
- **FCR** = total pakan (kg) / pertambahan biomassa (kg)
- **Biomassa** = populasi hidup x bobot rata-rata (g) / 1000
- **Laba/rugi** = total pendapatan - total modal

## Status
Dalam pengembangan (tugas besar).
