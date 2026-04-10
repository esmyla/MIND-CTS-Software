/// lib/features/auth/data/auth_repository.dart
///
/// Abstracts Supabase auth behind a simple interface.
/// When Supabase is not configured (Env.featureAuth == false), all methods
/// succeed immediately in "guest mode" so the app remains fully functional.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/env.dart';

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

sealed class AuthResult {
  const AuthResult();
}

final class AuthSuccess extends AuthResult {
  final bool isGuest;
  const AuthSuccess({this.isGuest = false});
}

final class AuthFailure extends AuthResult {
  final String message;
  const AuthFailure(this.message);
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class AuthRepository {
  AuthRepository();

  /// True when Supabase credentials are present and Supabase.instance is ready.
  bool get _hasSupabase => Env.featureAuth;

  SupabaseClient? get _client => _hasSupabase ? Supabase.instance.client : null;

  // ------------------------------------------------------------------
  // Current state
  // ------------------------------------------------------------------

  /// Returns the authenticated user's ID, or null if guest / unauthenticated.
  String? get currentUserId => _client?.auth.currentUser?.id;

  bool get isAuthenticated => _hasSupabase && (_client?.auth.currentUser != null);

  // ------------------------------------------------------------------
  // Sign in
  // ------------------------------------------------------------------

  Future<AuthResult> signIn(String email, String password) async {
    if (!_hasSupabase) {
      // Auth disabled build → auto-succeed as guest
      return const AuthSuccess(isGuest: true);
    }
    try {
      await _client!.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return const AuthSuccess();
    } on AuthException catch (e) {
      return AuthFailure(e.message);
    } catch (e) {
      return const AuthFailure('Unexpected error. Please try again.');
    }
  }

  // ------------------------------------------------------------------
  // Sign up
  // ------------------------------------------------------------------

  Future<AuthResult> signUp(String email, String password) async {
    if (!_hasSupabase) {
      return const AuthSuccess(isGuest: true);
    }
    try {
      final res = await _client!.auth.signUp(
        email: email.trim(),
        password: password,
      );
      if (res.user == null) {
        return const AuthFailure(
          'Account created — check your email to confirm.',
        );
      }
      return const AuthSuccess();
    } on AuthException catch (e) {
      return AuthFailure(e.message);
    } catch (e) {
      return const AuthFailure('Unexpected error. Please try again.');
    }
  }

  // ------------------------------------------------------------------
  // Sign out
  // ------------------------------------------------------------------

  Future<void> signOut() async {
    if (!_hasSupabase) return;
    try {
      await _client!.auth.signOut();
    } catch (e) {
      debugPrint('[AuthRepository] signOut error: $e');
    }
  }

  // ------------------------------------------------------------------
  // Auth state stream (for AuthGate)
  // ------------------------------------------------------------------

  Stream<AuthState>? get authStateStream => _client?.auth.onAuthStateChange;
}
