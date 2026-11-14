/// Pengaturan aplikasi.
///
/// Alamat server bisa diganti saat menjalankan, tanpa mengubah kode:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10/tanilog-repo/backend
///
/// Bawaan memakai "localhost": cocok untuk Chrome di laptop, dan untuk HP yang dicolok USB
/// bila dijalankan  adb reverse tcp:80 tcp:80  (lihat README).
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost/tanilog-repo/backend',
  );
}
