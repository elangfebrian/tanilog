import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/fmt.dart';
import '../core/theme.dart';
import '../state/siklus_state.dart';

({String teks, Color bg, Color fg}) _gaya(String status) {
  switch (status) {
    case 'sudah':
      return (teks: 'Sudah', bg: AppColors.soft, fg: AppColors.ink);
    case 'waktunya':
      return (teks: 'Waktunya', bg: const Color(0xFFFEF3C7), fg: AppColors.warn);
    case 'terlambat':
      return (teks: 'Terlambat', bg: const Color(0xFFFEE2E2), fg: const Color(0xFF991B1B));
    default:
      return (teks: 'Menunggu', bg: const Color(0xFFF1F5F9), fg: AppColors.muted);
  }
}

/// Kartu Beranda: jadwal pakan hari ini dengan tombol cepat "Beri" untuk yang belum dikerjakan.
class PengingatCard extends StatelessWidget {
  const PengingatCard({super.key, required this.data});

  final List<Map<String, dynamic>> data;

  int get _belum {
    int n = 0;
    for (final Map<String, dynamic> s in data) {
      for (final dynamic j in (s['jadwal'] as List<dynamic>)) {
        if ((j as Map)['status'] != 'sudah') {
          n++;
        }
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }
    final int belum = _belum;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: belum > 0 ? AppColors.gold : AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(belum > 0 ? Icons.notifications_active : Icons.check_circle,
                color: belum > 0 ? AppColors.gold : AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                belum > 0 ? 'Pakan hari ini: $belum belum diberikan' : 'Semua pakan hari ini sudah diberikan',
                style: AppText.h2,
              ),
            ),
          ]),
          for (final Map<String, dynamic> s in data) ...[
            const SizedBox(height: 12),
            Text('${s['label']}', style: AppText.title),
            for (final dynamic raw in (s['jadwal'] as List<dynamic>))
              _Slot(siklusId: s['siklus_id'] as int, j: Map<String, dynamic>.from(raw as Map)),
          ],
        ]),
      ),
    );
  }
}

class _Slot extends StatefulWidget {
  const _Slot({required this.siklusId, required this.j});

  final int siklusId;
  final Map<String, dynamic> j;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  bool _busy = false;

  Future<void> _beri() async {
    setState(() => _busy = true);
    try {
      await context
          .read<SiklusState>()
          .beriPakan(widget.siklusId, (widget.j['jumlah_kg'] as num).toDouble());
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String status = (widget.j['status'] ?? '') as String;
    final g = _gaya(status);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        SizedBox(width: 52, child: Text('${widget.j['jam']}', style: AppText.title)),
        Expanded(
          child: Text('${Fmt.number((widget.j['jumlah_kg'] as num), decimals: 1)} kg',
              style: AppText.body),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: g.bg, borderRadius: BorderRadius.circular(20)),
          child: Text(g.teks,
              style: TextStyle(color: g.fg, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        if (status != 'sudah') ...[
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: _busy ? null : _beri,
              child: _busy
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Beri'),
            ),
          ),
        ],
      ]),
    );
  }
}
