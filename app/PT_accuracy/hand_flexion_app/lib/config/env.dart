/// lib/config/env.dart
///
/// All environment variables and feature flags for the app.
/// Values come from --dart-define at build time or fall back to defaults.
/// NEVER commit real secrets. Set these in your CI/CD or local run config.
library;

class Env {
  Env._();

  // ---------------------------------------------------------------------------
  // Supabase
  // ---------------------------------------------------------------------------

  /// Your Supabase project URL.
  /// Pass via: flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Your Supabase anon (public) key.
  /// Pass via: flutter run --dart-define=SUPABASE_ANON_KEY=eyJ...
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  // ---------------------------------------------------------------------------
  // WebSocket backend
  // ---------------------------------------------------------------------------

  /// WebSocket URL for the Python flexion server.
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://localhost:8765',
  );

  // ---------------------------------------------------------------------------
  // Feature flags
  // ---------------------------------------------------------------------------

  /// Whether Supabase auth is enabled. Automatically false when credentials
  /// are missing; can also be forced off via --dart-define=FEATURE_AUTH=false.
  static bool get featureAuth {
    const flag = String.fromEnvironment('FEATURE_AUTH', defaultValue: 'auto');
    if (flag == 'false') return false;
    return supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  }

  /// Whether analytics telemetry is enabled (no-op if false).
  static const bool featureAnalytics = bool.fromEnvironment(
    'FEATURE_ANALYTICS',
    defaultValue: false,
  );

  /// Whether to show mock data on the Home dashboard (useful for demos).
  static const bool featureMockData = bool.fromEnvironment(
    'FEATURE_MOCK_DATA',
    defaultValue: true, // on by default until Supabase queries are wired
  );
}
