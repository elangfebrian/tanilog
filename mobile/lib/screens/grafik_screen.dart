import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/theme.dart';
import '../state/siklus_state.dart';

List<FlSpot> _titik(dynamic raw) {
  final List<dynamic> list = (raw as List<dynamic>?) ?? <dynamic>[];
  return list.map((e) {
    final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
    return FlSpot((m['hari'] as num).toDouble(), (m['bobot_g'] as num).toDouble());
  }).toList();
}

/// Grafik pertumbuhan: bobot aktual hasil sampling melawan kurva standar komoditas.
class GrafikScreen extends StatefulWidget {
  const GrafikScreen({super.key, required this.siklusId, required this.judul});

  final int siklusId;
  final String judul;

  @override
  State<GrafikScreen> createState() => _GrafikScreenState();
}

class _GrafikScreenState extends State<GrafikScreen> {
  List<FlSpot> _standar = <FlSpot>[];
  List<FlSpot> _aktual = <FlSpot>[];
  double _target = 0;
  int _durasi = 0;
  bool _loading = true;
  String? _error;

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
          await context.read<SiklusState>().api.get('/siklus/${widget.siklusId}/grafik');
      if (mounted) {
        setState(() {
          _standar = _titik(d['standar']);
          _aktual = _titik(d['aktual']);
          _target = ((d['target_bobot_panen_g'] as num?) ?? 0).toDouble();
          _durasi = ((d['durasi_panen_hari'] as num?) ?? 0).toInt();
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data grafik tidak dapat dibaca.');
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.bg, title: Text('Grafik · ${widget.judul}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center, style: AppText.body),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _muat, child: const Text('Coba lagi')),
                    ]),
                  ),
                )
              : _isi(),
    );
  }

  Widget _isi() {
    final double maxX = <double>[
      _durasi.toDouble(),
      ..._standar.map((e) => e.x),
      ..._aktual.map((e) => e.x),
    ].reduce((a, b) => a > b ? a : b);
    final double maxYData = <double>[
      _target,
      ..._standar.map((e) => e.y),
      ..._aktual.map((e) => e.y),
    ].reduce((a, b) => a > b ? a : b);
    final double maxY = (maxYData * 1.1).ceilToDouble();

    final bool adaAktual = _aktual.length > 1;
    final double? terakhir = _aktual.isEmpty ? null : _aktual.last.y;
    final double? std = terakhir == null ? null : _standarPada(_aktual.last.x);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Bobot rata-rata per ekor', style: AppText.h2),
        const SizedBox(height: 4),
        const Text('Garis tebal = bobot nyata dari sampling Anda. Garis putus = standar.',
            style: AppText.caption),
        const SizedBox(height: 16),
        SizedBox(
          height: 280,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: 0,
              maxY: maxY,
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  axisNameWidget: const Text('Hari ke-', style: AppText.caption),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: maxX <= 70 ? 10 : 20,
                    getTitlesWidget: (v, meta) =>
                        Text(v.toInt().toString(), style: AppText.caption),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, meta) =>
                        Text(Fmt.number(v), style: AppText.caption),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: _standar,
                  isCurved: false,
                  color: AppColors.gold,
                  barWidth: 2,
                  dashArray: <int>[6, 4],
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: _aktual,
                  isCurved: false,
                  color: AppColors.primary,
                  barWidth: 4,
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Wrap(spacing: 16, children: [
          _Legenda(AppColors.primary, 'Aktual'),
          _Legenda(AppColors.gold, 'Standar'),
        ]),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              !adaAktual
                  ? 'Catat sampling bobot minimal sekali lagi agar garis pertumbuhan terlihat.'
                  : _kesimpulan(terakhir!, std),
              style: AppText.body,
            ),
          ),
        ),
      ],
    );
  }

  /// Bobot standar pada hari tertentu (interpolasi linear antar titik standar).
  double? _standarPada(double hari) {
    if (_standar.isEmpty) {
      return null;
    }
    if (hari <= _standar.first.x) {
      return _standar.first.y;
    }
    for (int i = 1; i < _standar.length; i++) {
      final FlSpot a = _standar[i - 1];
      final FlSpot b = _standar[i];
      if (hari <= b.x) {
        final double t = (hari - a.x) / (b.x - a.x);
        return a.y + (b.y - a.y) * t;
      }
    }
    return _standar.last.y;
  }

  String _kesimpulan(double aktual, double? std) {
    if (std == null || std <= 0) {
      return 'Bobot terakhir ${Fmt.bobot(aktual)}.';
    }
    final double selisih = (aktual - std) / std * 100;
    final String arah = selisih >= 0 ? 'di atas' : 'di bawah';
    return 'Bobot terakhir ${Fmt.bobot(aktual)}, '
        '${Fmt.number(selisih.abs(), decimals: 1)}% $arah standar '
        '(${Fmt.bobot(std)}) pada hari yang sama.';
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda(this.warna, this.teks);

  final Color warna;
  final String teks;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 16, height: 4, color: warna),
        const SizedBox(width: 6),
        Text(teks, style: AppText.caption),
      ]);
}
