import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/theme.dart';
import '../state/siklus_state.dart';

const List<String> _kategoriModal = <String>[
  'bibit', 'pakan', 'obat', 'tenaga', 'listrik', 'lainnya'
];

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

double? _angka(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Rupiah gaya Indonesia: titik = pemisah ribuan ("22.000" -> 22000), koma = desimal.
double? _rupiah(String s) =>
    double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.'));

String _pesan(ApiException e) =>
    e.details.isEmpty ? e.message : e.details.values.join('\n');

/// Laba rugi satu siklus: transaksi modal, pendapatan, dan pencatatan panen.
class KeuanganScreen extends StatefulWidget {
  const KeuanganScreen(
      {super.key, required this.siklusId, required this.judul, required this.aktif});

  final int siklusId;
  final String judul;
  final bool aktif;

  @override
  State<KeuanganScreen> createState() => _KeuanganScreenState();
}

class _KeuanganScreenState extends State<KeuanganScreen> {
  Map<String, dynamic> _keu = <String, dynamic>{};
  List<Map<String, dynamic>> _transaksi = <Map<String, dynamic>>[];
  Map<String, dynamic>? _panen;
  bool _loading = true;
  String? _error;

  String get _base => '/siklus/${widget.siklusId}';
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
      final Map<String, dynamic> t = await _api.get('$_base/transaksi') as Map<String, dynamic>;
      Map<String, dynamic>? panen;
      try {
        final Map<String, dynamic> p = await _api.get('$_base/panen') as Map<String, dynamic>;
        panen = Map<String, dynamic>.from(p['panen'] as Map);
      } on ApiException catch (e) {
        if (e.status != 404) {
          rethrow;
        }
      }
      if (mounted) {
        setState(() {
          _keu = Map<String, dynamic>.from((t['keuangan'] as Map?) ?? {});
          _transaksi = ((t['transaksi'] as List<dynamic>?) ?? <dynamic>[])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _panen = panen;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data keuangan tidak dapat dibaca.');
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _tambahModal() async {
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormModal(siklusId: widget.siklusId),
    );
    if (ok == true) {
      _muat();
    }
  }

  Future<void> _catatPanen() async {
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormPanen(siklusId: widget.siklusId),
    );
    if (ok == true) {
      _toast('Panen dicatat, siklus selesai');
      _muat();
    }
  }

  Future<bool> _konfirmasi(String judul, String isi) async {
    final bool? ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(judul),
        content: Text(isi),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lanjut')),
        ],
      ),
    );
    return ya == true && mounted;
  }

  Future<void> _hapusTransaksi(Map<String, dynamic> t) async {
    if (!await _konfirmasi('Hapus transaksi?', 'Laba rugi akan dihitung ulang.')) {
      return;
    }
    try {
      await _api.delete('$_base/transaksi/${t['id']}');
      _muat();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _batalPanen() async {
    if (!await _konfirmasi('Batalkan panen?',
        'Pendapatan dari panen dihapus dan siklus kembali aktif.')) {
      return;
    }
    try {
      await _api.delete('$_base/panen');
      _toast('Panen dibatalkan');
      _muat();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sudahPanen = _panen != null;
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.bg, title: Text('Laba rugi · ${widget.judul}')),
      floatingActionButton: (!_loading && _error == null && !sudahPanen)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: _tambahModal,
              icon: const Icon(Icons.add),
              label: const Text('Tambah transaksi'),
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
              : RefreshIndicator(onRefresh: _muat, child: _isi(sudahPanen)),
    );
  }

  Widget _isi(bool sudahPanen) {
    final double laba = ((_keu['laba_rugi'] as num?) ?? 0).toDouble();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _Kartu(children: [
          const Text('Laba/rugi', style: AppText.caption),
          Text(Fmt.rupiah(laba),
              style: AppText.h1.copyWith(color: laba < 0 ? AppColors.danger : AppColors.primary)),
          const SizedBox(height: 12),
          Row(children: [
            _Ang('Modal', Fmt.rupiah((_keu['total_modal'] as num?) ?? 0)),
            _Ang('Pendapatan', Fmt.rupiah((_keu['total_pendapatan'] as num?) ?? 0)),
          ]),
        ]),
        if (sudahPanen)
          _Kartu(children: [
            const Text('Hasil panen', style: AppText.h2),
            const SizedBox(height: 8),
            Text('${Fmt.tanggal(_panen!['tanggal'] as String?)} · '
                '${Fmt.number((_panen!['jumlah_ekor'] as num?) ?? 0)} ekor · '
                '${Fmt.number((_panen!['bobot_total_kg'] as num?) ?? 0, decimals: 1)} kg'),
            Text('Harga ${Fmt.rupiah((_panen!['harga_per_kg'] as num?) ?? 0)}/kg', style: AppText.caption),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _batalPanen, child: const Text('Batalkan panen')),
          ])
        else if (widget.aktif)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: _catatPanen,
              icon: const Icon(Icons.agriculture),
              label: const Text('Catat panen'),
            ),
          ),
        const Text('Transaksi', style: AppText.h2),
        const SizedBox(height: 8),
        if (_transaksi.isEmpty)
          const Text('Belum ada transaksi.', style: AppText.caption)
        else
          for (final Map<String, dynamic> t in _transaksi)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${_cap(t['kategori'] as String? ?? '')}'
                  '${(t['keterangan'] ?? '') == '' ? '' : ' · ${t['keterangan']}'}'),
              subtitle: Text(Fmt.tanggal(t['tanggal'] as String?), style: AppText.caption),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  '${t['tipe'] == 'pendapatan' ? '+' : '-'}${Fmt.rupiah((t['jumlah_rp'] as num?) ?? 0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: t['tipe'] == 'pendapatan' ? AppColors.primary : AppColors.ink,
                  ),
                ),
                if (t['dari_panen'] != true)
                  IconButton(
                    tooltip: 'Hapus',
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: () => _hapusTransaksi(t),
                  ),
              ]),
            ),
      ],
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
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

/// Lembar isian modal (bottom sheet): kategori, jumlah, keterangan, tanggal.
class _FormModal extends StatefulWidget {
  const _FormModal({required this.siklusId});

  final int siklusId;

  @override
  State<_FormModal> createState() => _FormModalState();
}

class _FormModalState extends State<_FormModal> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _jumlah = TextEditingController();
  final TextEditingController _ket = TextEditingController();
  String _kategori = 'pakan';
  DateTime _tanggal = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _jumlah.dispose();
    _ket.dispose();
    super.dispose();
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
      await context.read<SiklusState>().api.post('/siklus/${widget.siklusId}/transaksi', {
        'tipe': 'modal',
        'kategori': _kategori,
        'tanggal': _iso(_tanggal),
        'jumlah_rp': _rupiah(_jumlah.text),
        if (_ket.text.trim().isNotEmpty) 'keterangan': _ket.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context, true);
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
              const Text('Tambah pengeluaran', style: AppText.h2),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final String k in _kategoriModal)
                  ChoiceChip(
                    label: Text(k[0].toUpperCase() + k.substring(1)),
                    selected: _kategori == k,
                    onSelected: (_) => setState(() => _kategori = k),
                  ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _jumlah,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Jumlah (Rp)'),
                validator: (v) {
                  final double? n = _rupiah(v ?? '');
                  return (n == null || n <= 0) ? 'Isi angka lebih dari 0' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ket,
                decoration: const InputDecoration(labelText: 'Keterangan (opsional)'),
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
              FilledButton(onPressed: _busy ? null : _simpan, child: const Text('Simpan')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lembar isian panen: jumlah ekor, bobot total, harga per kg.
class _FormPanen extends StatefulWidget {
  const _FormPanen({required this.siklusId});

  final int siklusId;

  @override
  State<_FormPanen> createState() => _FormPanenState();
}

class _FormPanenState extends State<_FormPanen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _ekor = TextEditingController();
  final TextEditingController _bobot = TextEditingController();
  final TextEditingController _harga = TextEditingController();
  DateTime _tanggal = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bobot.addListener(() => setState(() {}));
    _harga.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ekor.dispose();
    _bobot.dispose();
    _harga.dispose();
    super.dispose();
  }

  double get _total => (_angka(_bobot.text) ?? 0) * (_rupiah(_harga.text) ?? 0);

  Future<void> _simpan() async {
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SiklusState>().api.post('/siklus/${widget.siklusId}/panen', {
        'tanggal': _iso(_tanggal),
        'jumlah_ekor': int.tryParse(_ekor.text.trim()),
        'bobot_total_kg': _angka(_bobot.text),
        'harga_per_kg': _rupiah(_harga.text),
      });
      if (mounted) {
        Navigator.pop(context, true);
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

  String? _wajib(String? v, {bool bulat = false, bool rp = false}) {
    final double? n = rp ? _rupiah(v ?? '') : _angka(v ?? '');
    if (n == null || n <= 0) {
      return 'Isi angka lebih dari 0';
    }
    if (bulat && n != n.roundToDouble()) {
      return 'Harus bilangan bulat';
    }
    return null;
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
              const Text('Catat panen', style: AppText.h2),
              const SizedBox(height: 4),
              const Text('Menyimpan panen akan membuat pendapatan dan menutup siklus.',
                  style: AppText.caption),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ekor,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Jumlah ekor dipanen'),
                validator: (v) => _wajib(v, bulat: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bobot,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Bobot total (kg)'),
                validator: _wajib,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _harga,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Harga per kg (Rp)'),
                validator: (v) => _wajib(v, rp: true),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pilihTanggal,
                icon: const Icon(Icons.event),
                label: Text('Tanggal: ${Fmt.tanggal(_iso(_tanggal))}'),
              ),
              const SizedBox(height: 12),
              Text('Pendapatan: ${Fmt.rupiah(_total)}', style: AppText.title),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _simpan, child: const Text('Simpan panen')),
            ],
          ),
        ),
      ),
    );
  }
}
