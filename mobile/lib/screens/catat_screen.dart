import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/theme.dart';
import '../state/siklus_state.dart';

enum Jenis { pakan, kematian, sampling }

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Catat pakan, kematian, atau sampling bobot untuk satu siklus aktif.
class CatatScreen extends StatefulWidget {
  const CatatScreen({super.key, required this.siklusId, required this.judul});

  final int siklusId;
  final String judul;

  @override
  State<CatatScreen> createState() => _CatatScreenState();
}

class _CatatScreenState extends State<CatatScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _a = TextEditingController(); // angka utama
  final TextEditingController _b = TextEditingController(); // angka kedua / teks
  Jenis _jenis = Jenis.pakan;
  DateTime _tanggal = DateTime.now();
  bool _busy = false;
  bool _berubah = false;
  String? _error;
  List<Map<String, dynamic>> _riwayat = <Map<String, dynamic>>[];
  bool _loadRiwayat = true;

  @override
  void initState() {
    super.initState();
    _muatRiwayat();
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  String get _path => '/siklus/${widget.siklusId}/${_jenis.name}';

  Future<void> _muatRiwayat() async {
    setState(() => _loadRiwayat = true);
    try {
      final Map<String, dynamic> res = await context.read<SiklusState>().api.get(_path);
      final List<dynamic> raw = (res[_jenis.name] as List<dynamic>?) ?? <dynamic>[];
      if (mounted) {
        setState(() => _riwayat =
            raw.take(10).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {
      if (mounted) {
        setState(() => _riwayat = <Map<String, dynamic>>[]);
      }
    }
    if (mounted) {
      setState(() => _loadRiwayat = false);
    }
  }

  double? _angka(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  Map<String, dynamic> _body() {
    final String tgl = _iso(_tanggal);
    switch (_jenis) {
      case Jenis.pakan:
        final DateTime n = DateTime.now();
        final bool hariIni = _iso(n) == tgl;
        final String jam =
            '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
        return <String, dynamic>{
          'jumlah_kg': _angka(_a.text),
          'waktu': '$tgl ${hariIni ? jam : '12:00'}',
          if (_b.text.trim().isNotEmpty) 'catatan': _b.text.trim(),
        };
      case Jenis.kematian:
        return <String, dynamic>{
          'jumlah': int.tryParse(_a.text.trim()),
          'tanggal': tgl,
          if (_b.text.trim().isNotEmpty) 'penyebab': _b.text.trim(),
        };
      case Jenis.sampling:
        return <String, dynamic>{
          'bobot_rata_g': _angka(_a.text),
          'jumlah_sampel': int.tryParse(_b.text.trim()) ?? 1,
          'tanggal': tgl,
        };
    }
  }

  Future<void> _simpan() async {
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> res =
          await context.read<SiklusState>().api.post(_path, _body());
      _berubah = true;
      _a.clear();
      _b.clear();
      final Map<String, dynamic> r = (res['ringkasan'] as Map<String, dynamic>?) ?? {};
      if (mounted) {
        final num? sr = r['sr_persen'] as num?;
        final num? fcr = r['fcr'] as num?;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Tersimpan'
              '${sr != null ? ' · SR ${Fmt.percent(sr)}' : ''}'
              '${fcr != null ? ' · FCR ${Fmt.number(fcr, decimals: 2)}' : ''}'),
        ));
      }
      await _muatRiwayat();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = _pesan(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _pesan(ApiException e) {
    if (e.details.isEmpty) {
      return e.message;
    }
    return e.details.values.join('\n');
  }

  Future<void> _hapus(Map<String, dynamic> row) async {
    final bool? ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus catatan ini?'),
        content: const Text('Angka SR, FCR, dan estimasi akan dihitung ulang.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ya != true || !mounted) {
      return;
    }
    try {
      await context.read<SiklusState>().api.delete('$_path/${row['id']}');
      _berubah = true;
      await _muatRiwayat();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _pilihTanggal() async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (d != null) {
      setState(() => _tanggal = d);
    }
  }

  String _ringkasBaris(Map<String, dynamic> r) {
    switch (_jenis) {
      case Jenis.pakan:
        final String w = (r['waktu'] ?? '') as String;
        return '${Fmt.number((r['jumlah_kg'] as num?) ?? 0, decimals: 1)} kg · ${Fmt.tanggal(w)}';
      case Jenis.kematian:
        return '${Fmt.number((r['jumlah'] as num?) ?? 0)} ekor · ${Fmt.tanggal(r['tanggal'] as String?)}';
      case Jenis.sampling:
        return '${Fmt.bobot(((r['bobot_rata_g'] as num?) ?? 0).toDouble())} · ${Fmt.tanggal(r['tanggal'] as String?)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool pakan = _jenis == Jenis.pakan;
    final bool mati = _jenis == Jenis.kematian;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(_berubah);
        }
      },
      child: Scaffold(
        appBar: AppBar(backgroundColor: AppColors.bg, title: Text('Catat · ${widget.judul}')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<Jenis>(
              segments: const [
                ButtonSegment(value: Jenis.pakan, label: Text('Pakan')),
                ButtonSegment(value: Jenis.kematian, label: Text('Kematian')),
                ButtonSegment(value: Jenis.sampling, label: Text('Bobot')),
              ],
              selected: <Jenis>{_jenis},
              onSelectionChanged: (s) {
                setState(() {
                  _jenis = s.first;
                  _error = null;
                  _a.clear();
                  _b.clear();
                });
                _muatRiwayat();
              },
            ),
            const SizedBox(height: 16),
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _a,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: pakan
                          ? 'Jumlah pakan (kg)'
                          : mati
                              ? 'Jumlah mati (ekor)'
                              : 'Bobot rata-rata (gram)',
                    ),
                    validator: (v) {
                      final double? n = _angka(v ?? '');
                      if (n == null || n <= 0) {
                        return 'Isi angka lebih dari 0';
                      }
                      if (mati && n != n.roundToDouble()) {
                        return 'Harus bilangan bulat';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _b,
                    keyboardType: _jenis == Jenis.sampling ? TextInputType.number : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: pakan
                          ? 'Catatan (opsional)'
                          : mati
                              ? 'Penyebab (opsional)'
                              : 'Jumlah sampel (opsional, bawaan 1)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pilihTanggal,
                    icon: const Icon(Icons.event),
                    label: Text('Tanggal: ${Fmt.tanggal(_iso(_tanggal))}'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _simpan,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Simpan'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Catatan terakhir', style: AppText.h2),
            const SizedBox(height: 8),
            if (_loadRiwayat)
              const Padding(
                  padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (_riwayat.isEmpty)
              const Text('Belum ada catatan.', style: AppText.caption)
            else
              for (final Map<String, dynamic> r in _riwayat)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_ringkasBaris(r), style: AppText.body),
                  trailing: IconButton(
                    tooltip: 'Hapus',
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: () => _hapus(r),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
