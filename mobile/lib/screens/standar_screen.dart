import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../state/siklus_state.dart';

class _Baris {
  _Baris({String hari = '', String bobot = '', String pakan = ''})
      : hari = TextEditingController(text: hari),
        bobot = TextEditingController(text: bobot),
        pakan = TextEditingController(text: pakan);

  final TextEditingController hari;
  final TextEditingController bobot;
  final TextEditingController pakan;

  void dispose() {
    hari.dispose();
    bobot.dispose();
    pakan.dispose();
  }
}

String _teks(num? v) {
  if (v == null) {
    return '';
  }
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// Mengedit kurva standar pertumbuhan satu komoditas (hari ke-N -> bobot rata-rata gram).
class StandarScreen extends StatefulWidget {
  const StandarScreen({super.key, required this.komoditasId, required this.nama});

  final int komoditasId;
  final String nama;

  @override
  State<StandarScreen> createState() => _StandarScreenState();
}

class _StandarScreenState extends State<StandarScreen> {
  final List<_Baris> _baris = <_Baris>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _path => '/admin/komoditas/${widget.komoditasId}/standar';
  dynamic get _api => context.read<SiklusState>().api;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    for (final _Baris b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> d = await _api.get(_path) as Map<String, dynamic>;
      for (final _Baris b in _baris) {
        b.dispose();
      }
      _baris.clear();
      for (final dynamic e in (d['standar'] as List<dynamic>? ?? <dynamic>[])) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
        _baris.add(_Baris(
          hari: _teks(m['hari_ke'] as num?),
          bobot: _teks(m['bobot_standar_g'] as num?),
          pakan: _teks(m['pakan_standar_g'] as num?),
        ));
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Data standar tidak dapat dibaca.';
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  double? _n(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _simpan() async {
    final List<Map<String, dynamic>> titik = <Map<String, dynamic>>[];
    for (final _Baris b in _baris) {
      if (b.hari.text.trim().isEmpty && b.bobot.text.trim().isEmpty) {
        continue; // baris kosong diabaikan
      }
      titik.add(<String, dynamic>{
        'hari_ke': _n(b.hari.text),
        'bobot_standar_g': _n(b.bobot.text),
        if (b.pakan.text.trim().isNotEmpty) 'pakan_standar_g': _n(b.pakan.text),
      });
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.put(_path, <String, dynamic>{'standar': titik});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kurva disimpan')));
      }
      await _muat();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.details.isEmpty ? e.message : e.details.values.join('\n'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.bg, title: Text('Standar · ${widget.nama}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Bobot rata-rata per ekor pada hari tertentu. Dipakai untuk grafik dan estimasi panen. '
                  'Bobot harus naik seiring hari, minimal 2 titik.',
                  style: AppText.caption,
                ),
                const SizedBox(height: 12),
                for (int i = 0; i < _baris.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _baris[i].hari,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Hari ke-'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _baris[i].bobot,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Bobot (g)'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Hapus baris',
                        icon: const Icon(Icons.close, color: AppColors.danger),
                        onPressed: () => setState(() {
                          _baris.removeAt(i).dispose();
                        }),
                      ),
                    ]),
                  ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _baris.add(_Baris())),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah titik'),
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
                      : const Text('Simpan kurva'),
                ),
              ],
            ),
    );
  }
}
