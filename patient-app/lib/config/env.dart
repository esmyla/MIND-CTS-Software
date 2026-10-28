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

  /// WebSocket URL for the glove sensor bridge (sensor_ws_server.py).
  ///
  /// Separate process and port from the flexion server: flexion is camera-based
  /// and needs no hardware, while this one owns the USB serial connection to the
  /// glove. Either can run without the other.
  static const String sensorWsUrl = String.fromEnvironment(
    'SENSOR_WS_URL',
    defaultValue: 'ws://localhost:8766',
  );

  /// Why a WebSocket backend cannot be reached from this build, or null when
  /// it should work.
  ///
  /// The two Python backends need a camera and a USB serial port, so they run
  /// on the clinician's or patient's own machine — never on the web host. On a
  /// deployed HTTPS page that creates a hard browser limit: mixed-content rules
  /// block an insecure `ws://` connection outright, and the socket fails before
  /// it is ever attempted.
  ///
  /// Returning the reason lets the sensor screens say what is actually wrong
  /// instead of showing "not connected" forever on a site where connecting was
  /// never possible.
  static String? backendUnavailableReason(String url) {
    if (url.isEmpty) {
      return 'No backend is configured for this build.';
    }
    final pageIsSecure = Uri.base.scheme == 'https';
    final socketIsInsecure = url.startsWith('ws://');
    if (pageIsSecure && socketIsInsecure) {
      return 'This site is served over HTTPS, which cannot connect to an '
          'insecure ws:// backend. Run the app locally, or expose the backend '
          'over wss:// and rebuild with SENSOR_WS_URL / WS_URL set.';
    }
    return null;
  }

  /// True when the app is running from a deployed origin rather than a local
  /// dev server — used to explain hardware features that only work locally.
  static bool get isHostedBuild {
    final host = Uri.base.host;
    return host.isNotEmpty &&
        host != 'localhost' &&
        host != '127.0.0.1' &&
        host != '[::1]';
  }

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
