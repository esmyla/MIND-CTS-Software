/// lib/app.dart
///
/// Root of the Flutter widget tree.
/// [AuthGate] decides whether to show [LoginScreen] or [AppScaffold].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/presentation/login_screen.dart';
import 'features/auth/state/auth_provider.dart';
import 'routing/app_scaffold.dart';

class TherapyApp extends StatelessWidget {
  const TherapyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIND CTS — Physical Therapy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2D6A7D),
        fontFamily: 'Roboto',
      ),
      home: const AuthGate(),
    );
  }
}

/// Watches [sessionProvider] and routes to [LoginScreen] or [AppScaffold].
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return switch (session.status) {
      SessionStatus.unknown => const _SplashScreen(),
      SessionStatus.authenticated || SessionStatus.guest =>
        const AppScaffold(),
      SessionStatus.unauthenticated => const LoginScreen(),
    };
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.accessibility_new_rounded, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            CircularProgressIndicator(color: cs.primary),
          ],
        ),
      ),
    );
  }
}
