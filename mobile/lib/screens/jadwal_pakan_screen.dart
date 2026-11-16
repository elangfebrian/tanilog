import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/theme.dart';
import '../state/siklus_state.dart';

/// Mengatur jam dan takaran pakan harian satu siklus (dasar pengingat di Beranda).
class JadwalPakanScreen extends StatefulWidget {
  const JadwalPakanScreen({super.key, required this.siklusId, required this.judul});

  final int siklusId;
  final String judul;

  @override
  State<JadwalPakanScreen> createState() => _JadwalPakanScreenState();
}

class _JadwalPakanScreenState extends State<JadwalPakanScreen> {
  List<Map<String, dynamic>> _jadwal = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  String get _base => '/siklus/${widget.siklusId}/jadwal-pakan';
  dynamic get _api => context.read<SiklusState>().api;

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
      final Map<String, dynamic> d = await _api.get(_base) as Map<String, dynamic>;
      if (mounted) {
        setState(() => _jadwal = ((d['jadwal'] as List<dynamic>?) ?? <dynamic>[])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList());
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data jadwal tidak dapat dibaca.');
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _jam(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _tambah() async {
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
      helpText: 'Jam pemberian pakan',
    );
    if (t == null || !mounted) {
      return;
    }
    final TextEditingController c = TextEditingController();
    final String? kg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pakan jam ${_jam(t)}'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Jumlah (kg)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Simpan')),
        ],
      ),
    );
    c.dispose();
    if (kg == null || !mounted) {
      return;
    }
    final double? n = double.tryParse(kg.trim().replaceAll(',', '.'));
    if (n == null || n <= 0) {
      _toast('Jumlah harus angka lebih dari 0');
      return;
    }
    try {
      await _api.post(_base, <String, dynamic>{'jam': _jam(t), 'jumlah_kg': n});
      await _muat();
    } on ApiException catch (e) {
      _toast(e.details.isEmpty ? e.message : e.details.values.join('\n'));
    }
  }

  Future<void> _ubahAktif(Map<String, dynamic> j, bool aktif) async {
    try {
      await _api.put('$_base/${j['id']}', <String, dynamic>{
        'jam': j['jam'],
        'jumlah_kg': j['jumlah_kg'],
        'aktif': aktif,
      });
      await _muat();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _hapus(Map<String, dynamic> j) async {
    try {
      await _api.delete('$_base/${j['id']}');
      await _muat();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(true);
        }
      },
      child: Scaffold(
        appBar: AppBar(backgroundColor: AppColors.bg, title: Text('Jadwal pakan · ${widget.judul}')),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          onPressed: _tambah,
          icon: const Icon(Icons.add_alarm),
          label: const Text('Tambah jadwal'),
        ),
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
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      const Text(
                        'Beranda akan mengingatkan jadwal yang belum dikerjakan hari ini.',
                        style: AppText.caption,
                      ),
                      const SizedBox(height: 12),
                      if (_jadwal.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Belum ada jadwal. Tambahkan jam pemberian pakan.',
                              textAlign: TextAlign.center, style: AppText.caption),
                        )
                      else
                        for (final Map<String, dynamic> j in _jadwal)
                          Card(
                            elevation: 0,
                            color: Colors.white,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: AppColors.border),
                            ),
                            child: ListTile(
                              title: Text('${j['jam']} · ${Fmt.number(j['jumlah_kg'] as num, decimals: 1)} kg',
                                  style: AppText.title),
                              subtitle: Text(j['aktif'] == true ? 'Aktif' : 'Dimatikan',
                                  style: AppText.caption),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Switch(
                                  value: j['aktif'] == true,
                                  onChanged: (v) => _ubahAktif(j, v),
                                ),
                                IconButton(
                                  tooltip: 'Hapus',
                                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                                  onPressed: () => _hapus(j),
                                ),
                              ]),
                            ),
                          ),
                    ],
                  ),
      ),
    );
  }
}
