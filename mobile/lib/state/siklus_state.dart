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
    loading = false;
    notifyListeners();
  }

  /// Detail lengkap satu siklus (siklus + ringkasan + keuangan).
  Future<Map<String, dynamic>> detail(int id) => api.get('/siklus/$id');
}
