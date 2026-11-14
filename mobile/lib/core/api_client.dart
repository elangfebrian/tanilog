import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Error dari API, dengan pesan yang siap ditampilkan ke pengguna.
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.details = const <String, dynamic>{}});

  final String message;
  final int? status;
  final Map<String, dynamic> details;

  @override
  String toString() => message;
}

/// Pembungkus HTTP untuk REST API Tanilog: menambahkan token, membaca JSON,
/// dan mengubah error menjadi ApiException.
class ApiClient {
  ApiClient({
    required this.tokenProvider,
    required this.onUnauthorized,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String? Function() tokenProvider;
  final void Function() onUnauthorized;
  final http.Client _http;

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body: body);

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    Uri uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }

    final String? token = tokenProvider();
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final http.Response res;
    try {
      if (method == 'POST') {
        res = await _http.post(uri, headers: headers, body: jsonEncode(body ?? <String, dynamic>{}));
      } else if (method == 'PUT') {
        res = await _http.put(uri, headers: headers, body: jsonEncode(body ?? <String, dynamic>{}));
      } else if (method == 'DELETE') {
        res = await _http.delete(uri, headers: headers);
      } else {
        res = await _http.get(uri, headers: headers);
      }
    } on TimeoutException {
      throw ApiException('Server tidak merespons. Periksa koneksi lalu coba lagi.');
    } on http.ClientException {
      throw ApiException(
          'Tidak dapat terhubung ke server (${AppConfig.apiBaseUrl}). '
          'Pastikan Apache dan MySQL di XAMPP menyala.');
    }

    Map<String, dynamic> data = <String, dynamic>{};
    try {
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      }
    } catch (_) {
      // Bukan JSON (misalnya halaman error Apache): pakai pesan bawaan di bawah.
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }

    // Token ditolak: sesi habis. (Login yang gagal tidak membawa token, jadi tidak memicu ini.)
    if (res.statusCode == 401 && token != null) {
      onUnauthorized();
    }

    final dynamic rawDetails = data['details'];
    throw ApiException(
      (data['error'] as String?) ?? 'Terjadi kesalahan (kode ${res.statusCode})',
      status: res.statusCode,
      details: rawDetails is Map ? Map<String, dynamic>.from(rawDetails) : <String, dynamic>{},
    );
  }
}
