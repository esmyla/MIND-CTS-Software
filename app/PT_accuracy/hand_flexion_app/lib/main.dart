/// lib/main.dart
///
/// Application entry point.
/// Initialises Supabase (if credentials are available) then runs the app
/// wrapped in a Riverpod [ProviderScope].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Supabase initialisation ────────────────────────────────────────────────
  // Only initialise when credentials are present. If missing the app falls
  // back to guest mode automatically via SessionNotifier._init().
  if (Env.featureAuth) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }
  // ──────────────────────────────────────────────────────────────────────────

  runApp(
    const ProviderScope(
      child: TherapyApp(),
    ),
  );
}
