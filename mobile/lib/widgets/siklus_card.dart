import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/theme.dart';
import '../models/siklus.dart';

/// Warna chip per komoditas (sesuai desain).
({Color bg, Color fg}) warnaKomoditas(String nama) {
  final String n = nama.toLowerCase();
  if (n.contains('ayam')) {
    return (bg: const Color(0xFFFEF3C7), fg: const Color(0xFF78350F));
  }
  if (n.contains('bebek')) {
    return (bg: const Color(0xFFE0F2FE), fg: const Color(0xFF0C4A6E));
  }
  return (bg: AppColors.soft, fg: AppColors.ink);
}

class SiklusCard extends StatelessWidget {
  const SiklusCard({super.key, required this.s, required this.onTap});

  final SiklusRingkas s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = warnaKomoditas(s.komoditas);
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${s.unitNama} · Siklus ${s.siklusKe}', style: AppText.title),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration:
                        BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(20)),
                    child: Text(s.komoditas,
                        style: TextStyle(color: c.fg, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                s.aktif
                    ? 'Hari ke-${s.umurHari} dari ${s.durasiPanenHari}'
                    : 'Selesai · ${Fmt.tanggal(s.tanggalMulai)}',
                style: AppText.caption,
              ),
              if (s.aktif) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: s.progres,
                    minHeight: 8,
                    backgroundColor: AppColors.soft,
                    color: AppColors.primary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat('Populasi', Fmt.number(s.populasiHidup)),
                  _Stat('SR', s.srPersen == null ? '-' : Fmt.percent(s.srPersen!)),
                  _Stat('FCR', s.fcr == null ? '-' : Fmt.number(s.fcr!, decimals: 2)),
                  _Stat('Bobot', s.bobotTerakhirG > 0 ? Fmt.bobot(s.bobotTerakhirG) : '-'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          Text(value, style: AppText.title),
        ],
      ),
    );
  }
}
