import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/auth_state.dart';
import 'admin_screen.dart';
import 'laporan_screen.dart';
import 'siklus_list_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  Key _laporanKey = UniqueKey(); // diganti tiap tab Laporan dibuka agar datanya segar

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      const SiklusListScreen(beranda: true),
      const SiklusListScreen(beranda: false),
      LaporanScreen(key: _laporanKey),
      const _Akun(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          if (i == 2) {
            _laporanKey = UniqueKey();
          }
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Beranda'),
          NavigationDestination(icon: Icon(Icons.autorenew), label: 'Siklus'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Laporan'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Akun'),
        ],
      ),
    );
  }
}

class _Akun extends StatelessWidget {
  const _Akun();

  @override
  Widget build(BuildContext context) {
    final AuthState auth = context.watch<AuthState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Akun', style: AppText.h1),
            const SizedBox(height: 16),
            Text(auth.nama, style: AppText.title),
            Text(auth.email, style: AppText.caption),
            const SizedBox(height: 24),
            if (auth.isAdmin) ...[
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AdminScreen()),
                ),
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Panel admin'),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton(onPressed: auth.logout, child: const Text('Keluar')),
          ],
        ),
      ),
    );
  }
}
