import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'state/auth_state.dart';
import 'state/siklus_state.dart';

void main() {
  runApp(const TanilogApp());
}

class TanilogApp extends StatelessWidget {
  const TanilogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthState>(create: (_) => AuthState()..restore()),
        ChangeNotifierProxyProvider<AuthState, SiklusState>(
          create: (ctx) => SiklusState(ctx.read<AuthState>().api),
          update: (ctx, auth, prev) => prev ?? SiklusState(auth.api),
        ),
      ],
      child: MaterialApp(
        title: 'Tanilog',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Gate(),
      ),
    );
  }
}

/// Memilih layar: menunggu -> login -> beranda.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final AuthState auth = context.watch<AuthState>();
    if (!auth.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.loggedIn ? const HomeShell() : const LoginScreen();
  }
}
