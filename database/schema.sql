-- =====================================================================
-- Tanilog - Skema database (MySQL / MariaDB, cocok untuk XAMPP)
-- Aplikasi pencatat dan analisis budidaya lele, ayam pedaging, bebek
-- Cara pakai: import file ini lewat phpMyAdmin (tab Import) atau
--   mysql -u root < database/schema.sql
-- =====================================================================

CREATE DATABASE IF NOT EXISTS tanilog
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
USE tanilog;

-- Hapus tabel lama (urutan dari anak ke induk) supaya skrip bisa diulang
SET FOREIGN_KEY_CHECKS = 0;
DROP VIEW  IF EXISTS v_laba_rugi_siklus;
DROP VIEW  IF EXISTS v_ringkasan_siklus;
DROP VIEW  IF EXISTS v_siklus_dasar;
DROP TABLE IF EXISTS panen;
DROP TABLE IF EXISTS transaksi;
DROP TABLE IF EXISTS sampling_bobot;
DROP TABLE IF EXISTS catatan_kematian;
DROP TABLE IF EXISTS catatan_pakan;
DROP TABLE IF EXISTS jadwal_pakan;
DROP TABLE IF EXISTS siklus;
DROP TABLE IF EXISTS unit_budidaya;
DROP TABLE IF EXISTS standar_pertumbuhan;
DROP TABLE IF EXISTS komoditas;
DROP TABLE IF EXISTS users;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 1. Pengguna (peternak dan admin)
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nama          VARCHAR(100) NOT NULL,
  email         VARCHAR(120) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,           -- hasil password_hash() PHP, jangan simpan teks asli
  no_hp         VARCHAR(20)  NULL,
  role          ENUM('peternak','admin') NOT NULL DEFAULT 'peternak',
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. Komoditas (dikelola admin): lele, ayam pedaging, bebek
-- ---------------------------------------------------------------------
CREATE TABLE komoditas (
  id                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nama                VARCHAR(50)  NOT NULL,
  jenis               ENUM('ikan','unggas') NOT NULL,
  durasi_panen_hari   SMALLINT UNSIGNED NOT NULL,         -- umur standar panen
  target_bobot_panen_g DECIMAL(8,2) NOT NULL,             -- bobot target saat panen (gram/ekor)
  fcr_standar_maks    DECIMAL(4,2) NOT NULL,              -- FCR dianggap baik jika <= nilai ini
  sr_standar_min      DECIMAL(5,2) NOT NULL,              -- SR dianggap baik jika >= nilai ini (%)
  aktif               TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uq_komoditas_nama (nama)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. Standar pertumbuhan per komoditas (dikelola admin)
--    Dipakai untuk grafik "aktual vs standar" dan estimasi panen
-- ---------------------------------------------------------------------
CREATE TABLE standar_pertumbuhan (
  id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
  komoditas_id     INT UNSIGNED NOT NULL,
  hari_ke          SMALLINT UNSIGNED NOT NULL,
  bobot_standar_g  DECIMAL(8,2) NOT NULL,                 -- gram per ekor
  pakan_standar_g  DECIMAL(8,2) NULL,                     -- anjuran pakan gram per ekor per hari
  PRIMARY KEY (id),
  UNIQUE KEY uq_standar (komoditas_id, hari_ke),
  CONSTRAINT fk_standar_komoditas FOREIGN KEY (komoditas_id)
    REFERENCES komoditas (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. Unit budidaya: kolam atau kandang milik pengguna
-- ---------------------------------------------------------------------
CREATE TABLE unit_budidaya (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    INT UNSIGNED NOT NULL,
  nama       VARCHAR(60) NOT NULL,                        -- misalnya "Kolam A1"
  tipe       ENUM('kolam','kandang') NOT NULL,
  kapasitas  INT UNSIGNED NULL,                           -- ekor maksimal (opsional)
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_unit_user_nama (user_id, nama),
  CONSTRAINT fk_unit_user FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. Siklus budidaya (satu periode tebar sampai panen pada satu unit)
-- ---------------------------------------------------------------------
CREATE TABLE siklus (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id         INT UNSIGNED NOT NULL,
  unit_id         INT UNSIGNED NOT NULL,
  komoditas_id    INT UNSIGNED NOT NULL,
  siklus_ke       SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  tanggal_mulai   DATE NOT NULL,                          -- tanggal tebar / chick-in
  populasi_awal   INT UNSIGNED NOT NULL,
  bobot_awal_g    DECIMAL(8,2) NOT NULL DEFAULT 0,        -- bobot rata-rata bibit (gram)
  status          ENUM('aktif','selesai','gagal') NOT NULL DEFAULT 'aktif',
  tanggal_selesai DATE NULL,
  catatan         VARCHAR(255) NULL,
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_siklus_unit_ke (unit_id, siklus_ke),
  KEY idx_siklus_user_status (user_id, status),
  CONSTRAINT fk_siklus_user      FOREIGN KEY (user_id)      REFERENCES users (id)         ON DELETE CASCADE,
  CONSTRAINT fk_siklus_unit      FOREIGN KEY (unit_id)      REFERENCES unit_budidaya (id) ON DELETE CASCADE,
  CONSTRAINT fk_siklus_komoditas FOREIGN KEY (komoditas_id) REFERENCES komoditas (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. Jadwal pakan (sumber data pengingat di aplikasi)
-- ---------------------------------------------------------------------
CREATE TABLE jadwal_pakan (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  siklus_id  INT UNSIGNED NOT NULL,
  jam        TIME NOT NULL,                               -- misalnya 07:00:00
  jumlah_kg  DECIMAL(8,2) NOT NULL,
  aktif      TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  KEY idx_jadwal_siklus (siklus_id),
  CONSTRAINT fk_jadwal_siklus FOREIGN KEY (siklus_id)
    REFERENCES siklus (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. Catatan harian: pakan, kematian, sampling bobot
-- ---------------------------------------------------------------------
CREATE TABLE catatan_pakan (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  siklus_id   INT UNSIGNED NOT NULL,
  waktu       DATETIME NOT NULL,
  jumlah_kg   DECIMAL(8,2) NOT NULL,
  catatan     VARCHAR(255) NULL,
  PRIMARY KEY (id),
  KEY idx_pakan_siklus_waktu (siklus_id, waktu),
  CONSTRAINT fk_pakan_siklus FOREIGN KEY (siklus_id)
    REFERENCES siklus (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE catatan_kematian (
  id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
  siklus_id INT UNSIGNED NOT NULL,
  tanggal   DATE NOT NULL,
  jumlah    INT UNSIGNED NOT NULL,
  penyebab  VARCHAR(120) NULL,
  PRIMARY KEY (id),
  KEY idx_mati_siklus_tgl (siklus_id, tanggal),
  CONSTRAINT fk_mati_siklus FOREIGN KEY (siklus_id)
    REFERENCES siklus (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE sampling_bobot (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  siklus_id      INT UNSIGNED NOT NULL,
  tanggal        DATE NOT NULL,
  jumlah_sampel  SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  bobot_rata_g   DECIMAL(8,2) NOT NULL,                   -- rata-rata gram per ekor
  PRIMARY KEY (id),
  KEY idx_sampling_siklus_tgl (siklus_id, tanggal),
  CONSTRAINT fk_sampling_siklus FOREIGN KEY (siklus_id)
    REFERENCES siklus (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 8. Panen dan keuangan
-- ---------------------------------------------------------------------

-- Hasil panen (satu per siklus). Saat panen dicatat, aplikasi juga membuat satu baris
-- transaksi 'pendapatan' yang menunjuk ke baris panen ini (transaksi.panen_id) dan menandai
-- siklus 'selesai'. Bila panen dibatalkan, transaksi pendapatannya ikut terhapus (CASCADE).
CREATE TABLE panen (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  siklus_id      INT UNSIGNED NOT NULL,
  tanggal        DATE NOT NULL,
  jumlah_ekor    INT UNSIGNED NOT NULL,
  bobot_total_kg DECIMAL(10,2) NOT NULL,
  harga_per_kg   DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_panen_siklus (siklus_id),
  CONSTRAINT fk_panen_siklus FOREIGN KEY (siklus_id)
    REFERENCES siklus (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Modal (biaya) dan pendapatan per siklus
CREATE TABLE transaksi (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  siklus_id  INT UNSIGNED NOT NULL,
  tipe       ENUM('modal','pendapatan') NOT NULL,
  kategori   ENUM('bibit','pakan','obat','tenaga','listrik','lainnya','penjualan') NOT NULL,
  tanggal    DATE NOT NULL,
  keterangan VARCHAR(150) NULL,
  jumlah_rp  DECIMAL(14,2) NOT NULL,
  panen_id   INT UNSIGNED NULL,                           -- terisi bila dibuat otomatis dari panen
  PRIMARY KEY (id),
  KEY idx_transaksi_siklus (siklus_id, tipe),
  CONSTRAINT fk_transaksi_siklus FOREIGN KEY (siklus_id)
    REFERENCES siklus (id) ON DELETE CASCADE,
  CONSTRAINT fk_transaksi_panen FOREIGN KEY (panen_id)
    REFERENCES panen (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- =====================================================================
-- VIEW: perhitungan otomatis (SR, FCR, estimasi panen, laba rugi)
-- =====================================================================

-- Tahap 1: angka dasar tiap siklus
CREATE VIEW v_siklus_dasar AS
SELECT
  s.id AS siklus_id,
  s.user_id,
  s.unit_id,
  s.komoditas_id,
  s.status,
  s.tanggal_mulai,
  s.populasi_awal,
  s.bobot_awal_g,
  DATEDIFF(COALESCE(s.tanggal_selesai, CURDATE()), s.tanggal_mulai) AS umur_hari,
  COALESCE(m.total_mati, 0)                        AS total_mati,
  s.populasi_awal - COALESCE(m.total_mati, 0)      AS populasi_hidup,
  COALESCE(p.total_pakan_kg, 0)                    AS total_pakan_kg,
  COALESCE(b.bobot_rata_g, s.bobot_awal_g)         AS bobot_terakhir_g,
  DATE_ADD(s.tanggal_mulai, INTERVAL k.durasi_panen_hari DAY) AS estimasi_panen_standar,
  k.fcr_standar_maks,
  k.sr_standar_min
FROM siklus s
JOIN komoditas k ON k.id = s.komoditas_id
LEFT JOIN (SELECT siklus_id, SUM(jumlah) AS total_mati
           FROM catatan_kematian GROUP BY siklus_id) m ON m.siklus_id = s.id
LEFT JOIN (SELECT siklus_id, SUM(jumlah_kg) AS total_pakan_kg
           FROM catatan_pakan GROUP BY siklus_id) p ON p.siklus_id = s.id
LEFT JOIN sampling_bobot b
       ON b.id = (SELECT b2.id FROM sampling_bobot b2
                  WHERE b2.siklus_id = s.id
                  ORDER BY b2.tanggal DESC, b2.id DESC LIMIT 1);

-- Tahap 2: SR dan FCR
--   SR  = populasi hidup / populasi awal x 100
--   FCR = total pakan (kg) / pertambahan biomassa (kg)
--         biomassa = populasi hidup x bobot rata-rata / 1000
CREATE VIEW v_ringkasan_siklus AS
SELECT
  d.*,
  ROUND(d.populasi_hidup / NULLIF(d.populasi_awal, 0) * 100, 2) AS sr_persen,
  ROUND(d.populasi_hidup * d.bobot_terakhir_g / 1000, 2)        AS biomassa_kini_kg,
  ROUND(d.total_pakan_kg /
        NULLIF((d.populasi_hidup * d.bobot_terakhir_g
                - d.populasi_awal * d.bobot_awal_g) / 1000, 0), 2) AS fcr
FROM v_siklus_dasar d;

-- Laba rugi per siklus
CREATE VIEW v_laba_rugi_siklus AS
SELECT
  s.id AS siklus_id,
  s.user_id,
  COALESCE(SUM(CASE WHEN t.tipe = 'modal'      THEN t.jumlah_rp END), 0) AS total_modal,
  COALESCE(SUM(CASE WHEN t.tipe = 'pendapatan' THEN t.jumlah_rp END), 0) AS total_pendapatan,
  COALESCE(SUM(CASE WHEN t.tipe = 'pendapatan' THEN t.jumlah_rp END), 0)
  - COALESCE(SUM(CASE WHEN t.tipe = 'modal'    THEN t.jumlah_rp END), 0) AS laba_rugi
FROM siklus s
LEFT JOIN transaksi t ON t.siklus_id = s.id
GROUP BY s.id, s.user_id;

-- =====================================================================
-- DATA AWAL (seed) - komoditas dan standar pertumbuhan
-- Angka standar di bawah hanya contoh awal; sesuaikan dengan referensi
-- (jurnal, penyuluh perikanan/peternakan) lalu cantumkan di artikel.
-- =====================================================================
INSERT INTO komoditas (id, nama, jenis, durasi_panen_hari, target_bobot_panen_g, fcr_standar_maks, sr_standar_min) VALUES
  (1, 'Lele',         'ikan',   60, 250.00, 1.30, 85.00),
  (2, 'Ayam pedaging','unggas', 32, 1800.00, 1.60, 92.00),
  (3, 'Bebek pedaging','unggas', 50, 2000.00, 2.80, 90.00);

INSERT INTO standar_pertumbuhan (komoditas_id, hari_ke, bobot_standar_g) VALUES
  (1, 0, 5),   (1, 10, 15),  (1, 20, 40),  (1, 30, 80),  (1, 40, 120), (1, 45, 140), (1, 60, 250),
  (2, 0, 42),  (2, 7, 180),  (2, 14, 450), (2, 21, 900), (2, 28, 1500),(2, 32, 1800),
  (3, 0, 50),  (3, 14, 400), (3, 28, 1100),(3, 42, 1700),(3, 50, 2000);

-- =====================================================================
-- DATA CONTOH untuk pengembangan dan demo (boleh dihapus nanti)
-- Kata sandi contoh: admin@tanilog.test -> admin123
--                    budi@tanilog.test  -> peternak123
-- =====================================================================
INSERT INTO users (id, nama, email, password_hash, no_hp, role) VALUES
  (1, 'Admin Tanilog', 'admin@tanilog.test', '$2y$10$ObjgNzGQqZL.Zzce95k0O.sE7s87MXrEDaANnN3sJx8f4QsbS5urK', NULL, 'admin'),
  (2, 'Budi Santoso',  'budi@tanilog.test',  '$2y$10$h/Cz2rtFDx7ReLITK0OwVOjHfAarQnOu9d2uCFOdn5O2EjTvkmeqe', '081234567890', 'peternak');

INSERT INTO unit_budidaya (id, user_id, nama, tipe, kapasitas) VALUES
  (1, 2, 'Kolam A1',   'kolam',   2500),
  (2, 2, 'Kandang B',  'kandang', 600),
  (3, 2, 'Kandang C',  'kandang', 300);

INSERT INTO siklus (id, user_id, unit_id, komoditas_id, siklus_ke, tanggal_mulai, populasi_awal, bobot_awal_g, status, tanggal_selesai) VALUES
  (1, 2, 1, 1, 3, '2026-06-20', 2000, 5.00,  'selesai', '2026-08-19'),
  (2, 2, 1, 1, 4, '2026-09-22', 2000, 5.00,  'aktif',   NULL),
  (3, 2, 2, 2, 2, '2026-10-16', 500,  42.00, 'aktif',   NULL),
  (4, 2, 3, 3, 1, '2026-10-07', 250,  50.00, 'aktif',   NULL);

INSERT INTO jadwal_pakan (siklus_id, jam, jumlah_kg) VALUES
  (2, '07:00:00', 12.50), (2, '12:00:00', 12.50), (2, '17:00:00', 12.50);

INSERT INTO catatan_pakan (siklus_id, waktu, jumlah_kg, catatan) VALUES
  (2, '2026-10-15 07:00:00', 215.50, 'Rekap pakan 22 Sep - 4 Nov (data contoh)'),
  (2, '2026-11-05 07:10:00', 12.50, NULL),
  (2, '2026-11-05 17:05:00', 12.50, NULL),
  (2, '2026-11-06 07:10:00', 12.50, NULL);

INSERT INTO catatan_kematian (siklus_id, tanggal, jumlah, penyebab) VALUES
  (2, '2026-10-10', 40, 'Adaptasi awal'),
  (2, '2026-10-25', 81, 'Kualitas air'),
  (2, '2026-11-05', 3,  NULL);

INSERT INTO sampling_bobot (siklus_id, tanggal, jumlah_sampel, bobot_rata_g) VALUES
  (2, '2026-10-02', 20, 15.00),
  (2, '2026-10-12', 20, 35.00),
  (2, '2026-10-22', 20, 70.00),
  (2, '2026-11-01', 20, 112.00),
  (2, '2026-11-05', 20, 128.00);

INSERT INTO transaksi (siklus_id, tipe, kategori, tanggal, keterangan, jumlah_rp) VALUES
  (2, 'modal', 'bibit',   '2026-09-22', 'Bibit lele 2.000 ekor', 700000),
  (2, 'modal', 'pakan',   '2026-10-01', 'Pakan pelet tahap awal', 1200000),
  (2, 'modal', 'pakan',   '2026-10-25', 'Pakan pelet tahap lanjut', 1344000),
  (2, 'modal', 'obat',    '2026-10-26', 'Probiotik dan obat', 150000);

-- Siklus 1 (lele, Kolam A1, sudah dipanen) sebagai pembanding siklus 4
INSERT INTO catatan_pakan (siklus_id, waktu, jumlah_kg, catatan) VALUES
  (1, '2026-06-30 07:00:00', 520.00, 'Rekap pakan seluruh siklus (data contoh)');
INSERT INTO catatan_kematian (siklus_id, tanggal, jumlah, penyebab) VALUES
  (1, '2026-07-10', 150, 'Rekap kematian seluruh siklus (data contoh)');
INSERT INTO sampling_bobot (siklus_id, tanggal, jumlah_sampel, bobot_rata_g) VALUES
  (1, '2026-08-18', 20, 245.00);
INSERT INTO panen (id, siklus_id, tanggal, jumlah_ekor, bobot_total_kg, harga_per_kg) VALUES
  (1, 1, '2026-08-19', 1850, 450.00, 21000.00);
INSERT INTO transaksi (siklus_id, tipe, kategori, tanggal, keterangan, jumlah_rp, panen_id) VALUES
  (1, 'modal',      'bibit',     '2026-06-20', 'Bibit lele 2.000 ekor', 700000,  NULL),
  (1, 'modal',      'pakan',     '2026-07-15', 'Pakan pelet',           6240000, NULL),
  (1, 'modal',      'obat',      '2026-07-20', 'Probiotik dan obat',    180000,  NULL),
  (1, 'pendapatan', 'penjualan', '2026-08-19', 'Panen 450 kg',          9450000, 1);
