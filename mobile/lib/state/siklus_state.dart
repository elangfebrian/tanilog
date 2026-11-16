import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/siklus.dart';

/// Daftar siklus + detail yang sedang dibuka.
class SiklusState extends ChangeNotifier {
  SiklusState(this.api);

  final ApiClient api;

  List<SiklusRingkas> daftar = <SiklusRingkas>[];
  bool loading = false;
  String? error;

  /// Pengingat pakan hari ini (GET /pengingat/hari-ini): satu entri per siklus aktif berjadwal.
  List<Map<String, dynamic>> pengingat = <Map<String, dynamic>>[];

  Future<void> muat() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final Map<String, dynamic> res = await api.get('/siklus');
      final List<dynamic> raw = (res['siklus'] as List<dynamic>?) ?? <dynamic>[];
      daftar = raw.map((e) => SiklusRingkas(Map<String, dynamic>.from(e as Map))).toList();
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Data dari server tidak dapat dibaca.';
    }
    await muatPengingat();
    loading = false;
    notifyListeners();
  }

  /// Gagal memuat pengingat tidak boleh merusak daftar siklus, jadi errornya diabaikan.
  Future<void> muatPengingat() async {
    try {
      final Map<String, dynamic> res = await api.get('/pengingat/hari-ini');
      pengingat = ((res['pengingat'] as List<dynamic>?) ?? <dynamic>[])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      pengingat = <Map<String, dynamic>>[];
    }
    notifyListeners();
  }

  /// Menandai satu jadwal sudah dikerjakan: mencatat pakan sejumlah yang dijadwalkan.
  Future<void> beriPakan(int siklusId, double jumlahKg) async {
    await api.post('/siklus/$siklusId/pakan', <String, dynamic>{'jumlah_kg': jumlahKg});
    await muat();
  }

  /// Detail lengkap satu siklus (siklus + ringkasan + keuangan).
  Future<Map<String, dynamic>> detail(int id) => api.get('/siklus/$id');
}
