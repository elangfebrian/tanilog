double? _d(dynamic v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
int _i(dynamic v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);

/// Satu baris pada daftar siklus (GET /siklus).
class SiklusRingkas {
  SiklusRingkas(Map<String, dynamic> j)
      : id = _i(j['id']),
        siklusKe = _i(j['siklus_ke']),
        unitNama = (j['unit_nama'] ?? '') as String,
        komoditas = (j['komoditas'] ?? '') as String,
        durasiPanenHari = _i(j['durasi_panen_hari']),
        status = (j['status'] ?? '') as String,
        tanggalMulai = (j['tanggal_mulai'] ?? '') as String,
        umurHari = _i(j['umur_hari']),
        populasiAwal = _i(j['populasi_awal']),
        populasiHidup = _i(j['populasi_hidup']),
        srPersen = _d(j['sr_persen']),
        totalPakanKg = _d(j['total_pakan_kg']) ?? 0,
        bobotTerakhirG = _d(j['bobot_terakhir_g']) ?? 0,
        fcr = _d(j['fcr']);

  final int id, siklusKe, durasiPanenHari, umurHari, populasiAwal, populasiHidup;
  final String unitNama, komoditas, status, tanggalMulai;
  final double? srPersen, fcr;
  final double totalPakanKg, bobotTerakhirG;

  bool get aktif => status == 'aktif';

  /// Kemajuan menuju umur panen standar, 0..1.
  double get progres =>
      durasiPanenHari <= 0 ? 0 : (umurHari / durasiPanenHari).clamp(0.0, 1.0).toDouble();
}
