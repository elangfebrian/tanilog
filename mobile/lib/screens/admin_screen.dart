import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/theme.dart';
import '../state/siklus_state.dart';
import 'standar_screen.dart';

double? _angka(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Panel admin: ringkasan sistem dan pengelolaan komoditas beserta standarnya.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic> _ring = <String, dynamic>{};
  List<Map<String, dynamic>> _kom = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

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
      final Map<String, dynamic> r = await _api.get('/admin/ringkasan') as Map<String, dynamic>;
      final Map<String, dynamic> k = await _api.get('/admin/komoditas') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _ring = r;
          _kom = ((k['komoditas'] as List<dynamic>?) ?? <dynamic>[])
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
        setState(() => _error = 'Data admin tidak dapat dibaca.');
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _form([Map<String, dynamic>? k]) async {
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormKomoditas(awal: k),
    );
    if (ok == true) {
      _muat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.bg, title: const Text('Panel admin')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _form(),
        icon: const Icon(Icons.add),
        label: const Text('Komoditas'),
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
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _Stat('Peternak', '${_ring['peternak'] ?? 0}'),
                        _Stat('Unit', '${_ring['unit'] ?? 0}'),
                        _Stat('Siklus aktif', '${_ring['siklus_aktif'] ?? 0}'),
                        _Stat('Siklus selesai', '${_ring['siklus_selesai'] ?? 0}'),
                      ]),
                      const SizedBox(height: 20),
                      const Text('Komoditas', style: AppText.h2),
                      const SizedBox(height: 8),
                      for (final Map<String, dynamic> k in _kom)
                        Card(
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
                                Expanded(child: Text('${k['nama']}', style: AppText.title)),
                                if (k['aktif'] != true)
                                  const Text('Nonaktif',
                                      style: TextStyle(color: AppColors.danger, fontSize: 13)),
                              ]),
                              Text(
                                '${k['jenis']} · panen ${k['durasi_panen_hari']} hari · '
                                '${Fmt.bobot((k['target_bobot_panen_g'] as num).toDouble())} · '
                                'FCR ≤ ${Fmt.number(k['fcr_standar_maks'] as num, decimals: 2)} · '
                                'SR ≥ ${Fmt.number(k['sr_standar_min'] as num, decimals: 0)}%',
                                style: AppText.caption,
                              ),
                              Text('${k['jumlah_titik']} titik standar · dipakai ${k['jumlah_siklus']} siklus',
                                  style: AppText.caption),
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                                    onPressed: () => _form(k),
                                    child: const Text('Ubah'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                                    onPressed: () async {
                                      await Navigator.of(context).push(MaterialPageRoute<void>(
                                        builder: (_) => StandarScreen(
                                            komoditasId: k['id'] as int, nama: '${k['nama']}'),
                                      ));
                                      if (mounted) {
                                        _muat();
                                      }
                                    },
                                    child: const Text('Kurva standar'),
                                  ),
                                ),
                              ]),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.caption),
          Text(value, style: AppText.value),
        ]),
      );
}

class _FormKomoditas extends StatefulWidget {
  const _FormKomoditas({this.awal});

  final Map<String, dynamic>? awal;

  @override
  State<_FormKomoditas> createState() => _FormKomoditasState();
}

class _FormKomoditasState extends State<_FormKomoditas> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _durasi;
  late final TextEditingController _target;
  late final TextEditingController _fcr;
  late final TextEditingController _sr;
  late String _jenis;
  late bool _aktif;
  bool _busy = false;
  String? _error;

  bool get _edit => widget.awal != null;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? a = widget.awal;
    String t(dynamic v) => v == null ? '' : '$v';
    _nama = TextEditingController(text: t(a?['nama']));
    _durasi = TextEditingController(text: t(a?['durasi_panen_hari']));
    _target = TextEditingController(text: t(a?['target_bobot_panen_g']));
    _fcr = TextEditingController(text: t(a?['fcr_standar_maks']));
    _sr = TextEditingController(text: t(a?['sr_standar_min']));
    _jenis = (a?['jenis'] as String?) ?? 'ikan';
    _aktif = (a?['aktif'] as bool?) ?? true;
  }

  @override
  void dispose() {
    _nama.dispose();
    _durasi.dispose();
    _target.dispose();
    _fcr.dispose();
    _sr.dispose();
    super.dispose();
  }

  String? _wajibAngka(String? v) {
    final double? n = _angka(v ?? '');
    return (n == null || n <= 0) ? 'Isi angka lebih dari 0' : null;
  }

  Future<void> _simpan() async {
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Map<String, dynamic> body = <String, dynamic>{
      'nama': _nama.text.trim(),
      'jenis': _jenis,
      'durasi_panen_hari': int.tryParse(_durasi.text.trim()),
      'target_bobot_panen_g': _angka(_target.text),
      'fcr_standar_maks': _angka(_fcr.text),
      'sr_standar_min': _angka(_sr.text),
      'aktif': _aktif,
    };
    try {
      final dynamic api = context.read<SiklusState>().api;
      if (_edit) {
        await api.put('/admin/komoditas/${widget.awal!['id']}', body);
      } else {
        await api.post('/admin/komoditas', body);
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_edit ? 'Ubah komoditas' : 'Komoditas baru', style: AppText.h2),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nama,
                decoration: const InputDecoration(labelText: 'Nama'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ikan', label: Text('Ikan')),
                  ButtonSegment(value: 'unggas', label: Text('Unggas')),
                ],
                selected: <String>{_jenis},
                onSelectionChanged: (s) => setState(() => _jenis = s.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _durasi,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Durasi panen standar (hari)'),
                validator: (v) {
                  final int? n = int.tryParse((v ?? '').trim());
                  return (n == null || n <= 0) ? 'Isi bilangan bulat lebih dari 0' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _target,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Target bobot panen (gram/ekor)'),
                validator: _wajibAngka,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fcr,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'FCR standar maksimal'),
                validator: _wajibAngka,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sr,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'SR standar minimal (%)'),
                validator: (v) {
                  final double? n = _angka(v ?? '');
                  return (n == null || n < 0 || n > 100) ? 'Isi angka 0 sampai 100' : null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif (muncul di pilihan siklus baru)'),
                value: _aktif,
                onChanged: (v) => setState(() => _aktif = v),
              ),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
                const SizedBox(height: 8),
              ],
              FilledButton(onPressed: _busy ? null : _simpan, child: const Text('Simpan')),
            ],
          ),
        ),
      ),
    );
  }
}
