import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../state/auth_state.dart';
import '../state/siklus_state.dart';
import '../widgets/siklus_card.dart';
import 'siklus_detail_screen.dart';

/// Dipakai untuk tab Beranda (hanya siklus aktif) dan tab Siklus (semua).
class SiklusListScreen extends StatefulWidget {
  const SiklusListScreen({super.key, required this.beranda});

  final bool beranda;

  @override
  State<SiklusListScreen> createState() => _SiklusListScreenState();
}

class _SiklusListScreenState extends State<SiklusListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SiklusState>().muat();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final SiklusState st = context.watch<SiklusState>();
    final AuthState auth = context.watch<AuthState>();
    final items = widget.beranda ? st.daftar.where((s) => s.aktif).toList() : st.daftar;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: st.muat,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (widget.beranda) ...[
              Text(auth.nama.isEmpty ? 'Halo' : 'Halo, ${auth.nama}', style: AppText.h1),
              Text(Fmt.hariIni(DateTime.now()), style: AppText.caption),
              const SizedBox(height: 16),
              const Text('Siklus aktif', style: AppText.h2),
            ] else
              const Text('Semua siklus', style: AppText.h1),
            const SizedBox(height: 12),
            if (st.loading && st.daftar.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (st.error != null)
              _Pesan(
                  icon: Icons.cloud_off,
                  teks: st.error!,
                  aksi: 'Coba lagi',
                  onAksi: st.muat)
            else if (items.isEmpty)
              const _Pesan(icon: Icons.inbox_outlined, teks: 'Belum ada siklus.')
            else
              for (final s in items)
                SiklusCard(
                  s: s,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => SiklusDetailScreen(siklusId: s.id)),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Pesan extends StatelessWidget {
  const _Pesan({required this.icon, required this.teks, this.aksi, this.onAksi});

  final IconData icon;
  final String teks;
  final String? aksi;
  final VoidCallback? onAksi;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 8),
          Text(teks, textAlign: TextAlign.center, style: AppText.body),
          if (aksi != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAksi, child: Text(aksi!)),
          ],
        ],
      ),
    );
  }
}
