import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';

/// Status login: menyimpan token di perangkat dan memegang ApiClient.
class AuthState extends ChangeNotifier {
  AuthState() {
    api = ApiClient(
      tokenProvider: () => _token,
      onUnauthorized: () {
        logout();
      },
    );
  }

  late final ApiClient api;
  String? _token;
  Map<String, dynamic>? _user;
  bool _ready = false;

  /// false selama token tersimpan masih dibaca saat aplikasi dibuka.
  bool get ready => _ready;
  bool get loggedIn => _token != null;
  String get nama => (_user?['nama'] as String?) ?? '';
  String get email => (_user?['email'] as String?) ?? '';

  Future<void> restore() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      final String? savedUser = prefs.getString('user');
      if (savedUser != null) {
        final dynamic decoded = jsonDecode(savedUser);
        if (decoded is Map<String, dynamic>) {
          _user = decoded;
        }
      }
    } catch (_) {
      _token = null;
      _user = null;
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) async {
    final Map<String, dynamic> data =
        await api.post('/auth/login', <String, dynamic>{'email': email, 'password': password});
    await _simpan(data);
  }

  Future<void> register({
    required String nama,
    required String email,
    required String password,
  }) async {
    final Map<String, dynamic> data = await api.post(
      '/auth/register',
      <String, dynamic>{'nama': nama, 'email': email, 'password': password},
    );
    await _simpan(data);
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('user');
    } catch (_) {
      // Gagal menghapus penyimpanan tidak boleh menghalangi keluar.
    }
  }

  Future<void> _simpan(Map<String, dynamic> data) async {
    _token = data['token'] as String?;
    final dynamic u = data['user'];
    _user = u is Map ? Map<String, dynamic>.from(u) : null;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token ?? '');
      await prefs.setString('user', jsonEncode(_user ?? <String, dynamic>{}));
    } catch (_) {
      // Tetap login untuk sesi ini walau penyimpanan gagal.
    }
    notifyListeners();
  }
}
