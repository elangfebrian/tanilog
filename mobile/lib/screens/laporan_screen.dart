import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/theme.dart';
import '../state/siklus_state.dart';
import '../widgets/siklus_card.dart';

num? _n(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);

/// Tab Laporan: membandingkan semua siklus (SR, FCR, laba rugi) dan menyorot yang terbaik.
class LaporanScreen extends StatefulWidget {
  const LaporanScreen({super.key});

  @override
  State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> {
  List<Map<String, dynamic>> _siklus = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  String? _filter; // nama komoditas, null = semua

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> d =
          await context.read<SiklusState>().api.get('/laporan/perbandingan');
      if (mounted) {
        setState(() {
          _siklus = ((d['siklus'] as List<dynamic>?) ?? <dynamic>[])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data laporan tidak dapat dibaca.');
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _terfilter =>
      _filter == null ? _siklus : _siklus.where((s) => s['komoditas'] == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _muat, child: _isi()),
    );
  }

  Widget _isi() {
    if (_error != null) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 48),
        Text(_error!, textAlign: TextAlign.center, style: AppText.body),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _muat, child: const Text('Coba lagi')),
      ]);
    }

    final List<String> komoditas = _siklus.map((s) => s['komoditas'] as String).toSet().toList();
    final List<Map<String, dynamic>> semua = _terfilter;
    final List<Map<String, dynamic>> selesai = semua.where((s) => s['status'] == 'selesai').toList();

    double? rata(String key) {
      final List<double> v = selesai
          .map((s) => _n(s[key]))
          .whereType<num>()
          .map((e) => e.toDouble())
          .toList();
      return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    }

    final double total =
        selesai.fold<double>(0, (a, s) => a + (_n(s['laba_rugi']) ?? 0).toDouble());
    Map<String, dynamic>? terbaik;
    for (final Map<String, dynamic> s in selesai) {
      if (terbaik == null || (_n(s['laba_rugi']) ?? 0) > (_n(terbaik['laba_rugi']) ?? 0)) {
        terbaik = s;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('Laporan', style: AppText.h1),
        const Text('Perbandingan antar siklus', style: AppText.caption),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          ChoiceChip(
              label: const Text('Semua'),
              selected: _filter == null,
              onSelected: (_) => setState(() => _filter = null)),
          for (final String k in komoditas)
            ChoiceChip(
                label: Text(k),
                selected: _filter == k,
                onSelected: (_) => setState(() => _filter = k)),
        ]),
        const SizedBox(height: 16),
        if (semua.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Belum ada siklus untuk dibandingkan.',
                textAlign: TextAlign.center, style: AppText.caption),
          )
        else ...[
          _Kartu(children: [
            const Text('Siklus selesai', style: AppText.caption),
            Text(
              selesai.isEmpty
                  ? 'Belum ada'
                  : '${selesai.length} siklus · ${Fmt.rupiah(total)}',
              style: AppText.value.copyWith(
                  color: total < 0 ? AppColors.danger : AppColors.primary),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _Ang('Rata-rata SR', rata('sr_persen') == null ? '-' : Fmt.percent(rata('sr_persen')!)),
              _Ang('Rata-rata FCR',
                  rata('fcr') == null ? '-' : Fmt.number(rata('fcr')!, decimals: 2)),
            ]),
            if (terbaik != null) ...[
              const SizedBox(height: 12),
              Text('Terbaik: ${terbaik['label']} (${Fmt.rupiah(_n(terbaik['laba_rugi']) ?? 0)})',
                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600)),
            ],
          ]),
          if (selesai.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('Laba/rugi per siklus selesai', style: AppText.h2),
            const SizedBox(height: 12),
            SizedBox(height: 220, child: _grafik(selesai)),
            const SizedBox(height: 16),
          ],
          const Text('Semua siklus', style: AppText.h2),
          const SizedBox(height: 8),
          for (final Map<String, dynamic> s in semua) _Baris(s: s),
        ],
      ],
    );
  }

  Widget _grafik(List<Map<String, dynamic>> data) {
    final List<double> nilai = data.map((s) => (_n(s['laba_rugi']) ?? 0).toDouble()).toList();
    final double maks = nilai.reduce((a, b) => a > b ? a : b);
    final double mins = nilai.reduce((a, b) => a < b ? a : b);
    final double atas = maks > 0 ? maks * 1.2 : 1;
    final double bawah = mins < 0 ? mins * 1.2 : 0;

    return BarChart(
      BarChartData(
        minY: bawah,
        maxY: atas,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (v, meta) => Text(
                '${Fmt.number(v / 1000000, decimals: 1)} jt',
                style: AppText.caption,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, meta) {
                final int i = v.toInt();
                if (i < 0 || i >= data.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${data[i]['unit_nama']} ·${data[i]['siklus_ke']}'.replaceAll('Kolam ', '').replaceAll('Kandang ', ''),
                      style: AppText.caption),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (int i = 0; i < nilai.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: nilai[i],
                width: 22,
                color: nilai[i] < 0 ? AppColors.danger : AppColors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
        ],
      ),
    );
  }
}

class _Baris extends StatelessWidget {
  const _Baris({required this.s});

  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final num? sr = _n(s['sr_persen']);
    final num? fcr = _n(s['fcr']);
    final num srMin = _n(s['sr_standar_min']) ?? 0;
    final num fcrMaks = _n(s['fcr_standar_maks']) ?? 99;
    final bool srBaik = sr != null && sr >= srMin;
    final bool fcrBaik = fcr != null && fcr <= fcrMaks;
    final double laba = (_n(s['laba_rugi']) ?? 0).toDouble();
    final bool aktif = s['status'] == 'aktif';
    final c = warnaKomoditas((s['komoditas'] ?? '') as String);

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${s['label']}', style: AppText.title)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(20)),
              child: Text('${s['komoditas']}',
                  style: TextStyle(color: c.fg, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
          Text(aktif ? 'Berjalan · hari ke-${s['umur_hari']}' : 'Selesai · ${s['umur_hari']} hari',
              style: AppText.caption),
          const SizedBox(height: 10),
          Row(children: [
            _Ang('SR', sr == null ? '-' : '${Fmt.percent(sr)} ${srBaik ? '✓' : '!'}',
                warna: sr == null ? null : (srBaik ? AppColors.primary : AppColors.danger)),
            _Ang('FCR', fcr == null ? '-' : '${Fmt.number(fcr, decimals: 2)} ${fcrBaik ? '✓' : '!'}',
                warna: fcr == null ? null : (fcrBaik ? AppColors.primary : AppColors.danger)),
            _Ang(aktif ? 'Laba berjalan' : 'Laba/rugi', Fmt.rupiah(laba),
                warna: laba < 0 ? AppColors.danger : AppColors.primary),
          ]),
        ]),
      ),
    );
  }
}

class _Kartu extends StatelessWidget {
  const _Kartu({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );
}

class _Ang extends StatelessWidget {
  const _Ang(this.label, this.value, {this.warna});

  final String label, value;
  final Color? warna;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.caption),
          Text(value, style: AppText.title.copyWith(color: warna ?? AppColors.ink)),
        ]),
      );
}
