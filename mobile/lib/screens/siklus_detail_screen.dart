import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/theme.dart';
import '../state/siklus_state.dart';
import 'catat_screen.dart';

num? _n(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);

class SiklusDetailScreen extends StatefulWidget {
  const SiklusDetailScreen({super.key, required this.siklusId});

  final int siklusId;

  @override
  State<SiklusDetailScreen> createState() => _SiklusDetailScreenState();
}

class _SiklusDetailScreenState extends State<SiklusDetailScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

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
      final Map<String, dynamic> d = await context.read<SiklusState>().detail(widget.siklusId);
      if (mounted) {
        setState(() => _data = d);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data dari server tidak dapat dibaca.');
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? sik = _data?['siklus'] as Map<String, dynamic>?;
    final Map<String, dynamic> r =
        (_data?['ringkasan'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> k =
        (_data?['keuangan'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> est =
        (r['estimasi_panen'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(sik == null ? 'Detail siklus' : '${sik['unit_nama']} · Siklus ${sik['siklus_ke']}'),
      ),
      floatingActionButton: (sik != null && sik['status'] == 'aktif')
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () async {
                final bool? berubah = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => CatatScreen(
                      siklusId: widget.siklusId,
                      judul: '${sik['unit_nama']} · Siklus ${sik['siklus_ke']}',
                    ),
                  ),
                );
                if (berubah == true) {
                  _muat();
                }
              },
              icon: const Icon(Icons.edit_note),
              label: const Text('Catat hari ini'),
            )
          : null,
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
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    children: [
                      _Kartu(judul: 'Estimasi panen', anak: [
                        Text(Fmt.tanggal(est['tanggal'] as String?), style: AppText.value),
                        Text(
                          est['sisa_hari'] == null
                              ? 'Belum ada perkiraan'
                              : '${_n(est['sisa_hari'])} hari lagi'
                                  '${est['metode'] == 'kurva_standar' ? ' · dari sampling bobot' : ' · berdasar durasi standar'}',
                          style: AppText.caption,
                        ),
                      ]),
                      _Kartu(judul: 'Performa', anak: [
                        Row(children: [
                          _Ang('Umur', '${r['umur_hari'] ?? '-'} hari'),
                          _Ang('Populasi', Fmt.number(_n(r['populasi_hidup']) ?? 0)),
                          _Ang('SR', _n(r['sr_persen']) == null ? '-' : Fmt.percent(_n(r['sr_persen'])!)),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          _Ang('FCR', _n(r['fcr']) == null ? '-' : Fmt.number(_n(r['fcr'])!, decimals: 2)),
                          _Ang('Pakan', '${Fmt.number(_n(r['total_pakan_kg']) ?? 0, decimals: 1)} kg'),
                          _Ang('Bobot', (_n(r['bobot_terakhir_g']) ?? 0) > 0
                              ? Fmt.bobot(_n(r['bobot_terakhir_g'])!.toDouble())
                              : '-'),
                        ]),
                      ]),
                      _Kartu(judul: 'Keuangan', anak: [
                        Row(children: [
                          _Ang('Modal', Fmt.rupiah(_n(k['total_modal']) ?? 0)),
                          _Ang('Pendapatan', Fmt.rupiah(_n(k['total_pendapatan']) ?? 0)),
                        ]),
                        const SizedBox(height: 12),
                        Text('Laba/rugi', style: AppText.caption),
                        Text(
                          Fmt.rupiah(_n(k['laba_rugi']) ?? 0),
                          style: AppText.value.copyWith(
                              color: (_n(k['laba_rugi']) ?? 0) < 0 ? AppColors.danger : AppColors.primary),
                        ),
                      ]),
                    ],
                  ),
                ),
    );
  }
}

class _Kartu extends StatelessWidget {
  const _Kartu({required this.judul, required this.anak});

  final String judul;
  final List<Widget> anak;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(judul, style: AppText.h2), const SizedBox(height: 8), ...anak],
        ),
      ),
    );
  }
}

class _Ang extends StatelessWidget {
  const _Ang(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.caption),
          Text(value, style: AppText.title),
        ]),
      );
}
