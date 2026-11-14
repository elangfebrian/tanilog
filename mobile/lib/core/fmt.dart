/// Pemformat angka dan tanggal gaya Indonesia (titik ribuan, koma desimal).
/// Ditulis sendiri agar tidak butuh paket tambahan.
class Fmt {
  static const List<String> _bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  static const List<String> _hari = [
    'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
  ];

  /// 1234567.5 -> "1.234.567,5" (decimals: 1)
  static String number(num value, {int decimals = 0}) {
    final String fixed = value.abs().toStringAsFixed(decimals);
    final bool isZero = double.parse(fixed) == 0;
    final List<String> parts = fixed.split('.');
    final String intPart = parts[0];

    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) {
        buf.write('.');
      }
      buf.write(intPart[i]);
    }
    String out = buf.toString();
    if (decimals > 0) {
      out = '$out,${parts[1]}';
    }
    return (value < 0 && !isZero) ? '-$out' : out;
  }

  /// 3394000 -> "Rp 3.394.000", -50000 -> "-Rp 50.000"
  static String rupiah(num value) {
    final int r = value.round();
    return r < 0 ? '-Rp ${number(-r)}' : 'Rp ${number(r)}';
  }

  /// 93.8 -> "93,8%"
  static String percent(num value) => '${number(value, decimals: 1)}%';

  /// Bobot dalam gram: 128 -> "128 g", 1500 -> "1,50 kg"
  static String bobot(double gram) {
    if (gram >= 1000) {
      return '${number(gram / 1000, decimals: 2)} kg';
    }
    final int decimals = gram == gram.roundToDouble() ? 0 : 1;
    return '${number(gram, decimals: decimals)} g';
  }

  /// "2026-11-23" -> "23 Nov 2026"
  static String tanggal(String? iso) {
    if (iso == null || iso.length < 10) {
      return '-';
    }
    final List<String> p = iso.substring(0, 10).split('-');
    if (p.length != 3) {
      return iso;
    }
    final int? m = int.tryParse(p[1]);
    final int? d = int.tryParse(p[2]);
    if (m == null || d == null || m < 1 || m > 12) {
      return iso;
    }
    return '$d ${_bulan[m - 1]} ${p[0]}';
  }

  /// "Minggu, 15 Nov 2026"
  static String hariIni(DateTime now) =>
      '${_hari[now.weekday - 1]}, ${now.day} ${_bulan[now.month - 1]} ${now.year}';
}
