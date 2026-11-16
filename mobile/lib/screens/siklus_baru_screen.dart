import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/theme.dart';
import '../state/siklus_state.dart';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

double? _angka(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Membuat siklus baru: pilih (atau buat) kolam/kandang, komoditas, tanggal, dan jumlah bibit.
class SiklusBaruScreen extends StatefulWidget {
  const SiklusBaruScreen({super.key});

  @override
  State<SiklusBaruScreen> createState() => _SiklusBaruScreenState();
}

class _SiklusBaruScreenState extends State<SiklusBaruScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _namaUnit = TextEditingController();
  final TextEditingController _kapasitas = TextEditingController();
  final TextEditingController _populasi = TextEditingController();
  final TextEditingController _bobot = TextEditingController();
  final TextEditingController _catatan = TextEditingController();

  List<Map<String, dynamic>> _unit = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _komoditas = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _loadError;

  int? _unitId; // null + _unitBaru = membuat unit baru
  bool _unitBaru = false;
  String _tipeBaru = 'kolam';
  int? _komId;
  DateTime _tanggal = DateTime.now();
  int? _unitDibuat; // unit yang sudah terlanjur dibuat bila langkah siklus gagal

  bool _busy = false;
  String? _error;

  dynamic get _api => context.read<SiklusState>().api;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _namaUnit.dispose();
    _kapasitas.dispose();
    _populasi.dispose();
    _bobot.dispose();
    _catatan.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _daftar(dynamic raw) => ((raw as List<dynamic>?) ?? <dynamic>[])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  Future<void> _muat() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final Map<String, dynamic> u = await _api.get('/unit') as Map<String, dynamic>;
      final Map<String, dynamic> k = await _api.get('/komoditas') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _unit = _daftar(u['unit']);
          _komoditas = _daftar(k['komoditas']);
          _unitBaru = _unit.isEmpty;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loadError = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Data tidak dapat dibaca.');
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  String _pesan(ApiException e) => e.details.isEmpty ? e.message : e.details.values.join('\n');

  Future<void> _pilihTanggal() async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (d != null) {
      setState(() => _tanggal = d);
    }
  }

  Future<void> _simpan() async {
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }
    if (_komId == null) {
      setState(() => _error = 'Pilih komoditas dulu.');
      return;
    }
    if (!_unitBaru && _unitId == null) {
      setState(() => _error = 'Pilih kolam/kandang dulu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      int unitId;
      if (_unitBaru) {
        if (_unitDibuat != null) {
          unitId = _unitDibuat!;
        } else {
          final Map<String, dynamic> res = await _api.post('/unit', <String, dynamic>{
            'nama': _namaUnit.text.trim(),
            'tipe': _tipeBaru,
            if (_kapasitas.text.trim().isNotEmpty) 'kapasitas': int.tryParse(_kapasitas.text.trim()),
          }) as Map<String, dynamic>;
          unitId = (res['unit'] as Map)['id'] as int;
          _unitDibuat = unitId;
        }
      } else {
        unitId = _unitId!;
      }

      await _api.post('/siklus', <String, dynamic>{
        'unit_id': unitId,
        'komoditas_id': _komId,
        'tanggal_mulai': _iso(_tanggal),
        'populasi_awal': int.tryParse(_populasi.text.trim()),
        if (_bobot.text.trim().isNotEmpty) 'bobot_awal_g': _angka(_bobot.text),
        if (_catatan.text.trim().isNotEmpty) 'catatan': _catatan.text.trim(),
      });
      if (mounted) {
        Navigator.of(context).pop(true);
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.bg, title: const Text('Siklus baru')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_loadError!, textAlign: TextAlign.center, style: AppText.body),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _muat, child: const Text('Coba lagi')),
                    ]),
                  ),
                )
              : _formulir(),
    );
  }

  Widget _formulir() {
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Kolam / kandang', style: AppText.h2),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final Map<String, dynamic> u in _unit)
              ChoiceChip(
                label: Text('${u['nama']}${(u['siklus_aktif'] as int? ?? 0) > 0 ? ' (terpakai)' : ''}'),
                selected: !_unitBaru && _unitId == u['id'],
                onSelected: (u['siklus_aktif'] as int? ?? 0) > 0
                    ? null
                    : (_) => setState(() {
                          _unitBaru = false;
                          _unitId = u['id'] as int;
                        }),
              ),
            ChoiceChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Baru'),
              selected: _unitBaru,
              onSelected: (_) => setState(() => _unitBaru = true),
            ),
          ]),
          if (_unitBaru) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _namaUnit,
              decoration: const InputDecoration(labelText: 'Nama (contoh: Kolam B2)'),
              validator: (v) => (_unitBaru && (v == null || v.trim().isEmpty)) ? 'Nama wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'kolam', label: Text('Kolam')),
                ButtonSegment(value: 'kandang', label: Text('Kandang')),
              ],
              selected: <String>{_tipeBaru},
              onSelectionChanged: (s) => setState(() => _tipeBaru = s.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _kapasitas,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Kapasitas ekor (opsional)'),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Komoditas', style: AppText.h2),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final Map<String, dynamic> k in _komoditas)
              ChoiceChip(
                label: Text('${k['nama']}'),
                selected: _komId == k['id'],
                onSelected: (_) => setState(() => _komId = k['id'] as int),
              ),
          ]),
          const SizedBox(height: 20),
          TextFormField(
            controller: _populasi,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Jumlah bibit awal (ekor)'),
            validator: (v) {
              final int? n = int.tryParse((v ?? '').trim());
              return (n == null || n <= 0) ? 'Isi bilangan bulat lebih dari 0' : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _bobot,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Bobot awal per ekor, gram (opsional)'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return null;
              }
              final double? n = _angka(v);
              return (n == null || n < 0) ? 'Isi angka 0 atau lebih' : null;
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pilihTanggal,
            icon: const Icon(Icons.event),
            label: Text('Mulai: ${Fmt.tanggal(_iso(_tanggal))}'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _catatan,
            decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _simpan,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Mulai siklus'),
          ),
        ],
      ),
    );
  }
}
