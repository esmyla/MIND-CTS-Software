/// lib/config/env.dart
///
/// Centralized environment configuration and feature flags.
/// Values come from --dart-define at build time or fall back to safe defaults.
///
/// ⚠️ NEVER commit real secrets.
/// Use local run configs or CI/CD environment variables.
library;

class Env {
  Env._();

  // ===========================================================================
  // SUPABASE
  // ===========================================================================

  /// Supabase project URL
  ///
  /// Example:
  /// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Supabase anon (public) API key
  ///
  /// Example:
  /// flutter run --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Whether valid Supabase credentials are available
  static bool get hasSupabaseCredentials => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // ===========================================================================
  // BACKENDS
  // ===========================================================================

  /// WebSocket URL for the Python flexion server
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://localhost:8765',
  );

  // ===========================================================================
  // FEATURE FLAGS
  // ===========================================================================

  /// Whether authentication is enabled.
  ///
  /// Behavior:
  /// - FEATURE_AUTH=true   → auth ON (requires Supabase credentials)
  /// - FEATURE_AUTH=false  → auth OFF (guest-only mode)
  /// - FEATURE_AUTH unset  → auto-enable if credentials are present
  ///
  /// Recommended:
  /// - Dev: auto (default)
  /// - Staging/Prod: FEATURE_AUTH=true
  static bool get featureAuth {
    const flag = String.fromEnvironment('FEATURE_AUTH', defaultValue: 'auto');

    if (flag == 'false') return false;

    if (flag == 'true') {
      return hasSupabaseCredentials;
    }

    // auto mode
    return hasSupabaseCredentials;
  }

  /// Whether analytics/telemetry is enabled
  static const bool featureAnalytics = bool.fromEnvironment(
    'FEATURE_ANALYTICS',
    defaultValue: false,
  );

  /// Whether to use mock data on the Home dashboard
  ///
  /// Useful while backend queries are still in progress.
  static const bool featureMockData = bool.fromEnvironment(
    'FEATURE_MOCK_DATA',
    defaultValue: true,
  );
}
