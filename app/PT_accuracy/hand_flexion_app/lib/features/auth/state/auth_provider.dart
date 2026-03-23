/// lib/features/auth/state/auth_provider.dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../../../config/env.dart';

// ---------------------------------------------------------------------------
// Repository provider (singleton)
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

enum SessionStatus { unknown, authenticated, guest, unauthenticated }

class SessionState {
  final SessionStatus status;
  final String? userId;
  final bool authBannerVisible; // shown when auth is disabled in this build

  const SessionState({
    this.status = SessionStatus.unknown,
    this.userId,
    this.authBannerVisible = false,
  });

  SessionState copyWith({
    SessionStatus? status,
    String? userId,
    bool? authBannerVisible,
  }) {
    return SessionState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      authBannerVisible: authBannerVisible ?? this.authBannerVisible,
    );
  }

  bool get isLoggedIn =>
      status == SessionStatus.authenticated || status == SessionStatus.guest;
}

// ---------------------------------------------------------------------------
// SessionNotifier
// ---------------------------------------------------------------------------

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier(this._repo) : super(const SessionState()) {
    _init();
  }

  final AuthRepository _repo;

  void _init() {
    if (!Env.featureAuth) {
      // Auth disabled in this build — default to unauthenticated (show login
      // with banner) so user can still tap Skip.
      state = state.copyWith(
        status: SessionStatus.unauthenticated,
        authBannerVisible: true,
      );
      return;
    }

    // Restore existing Supabase session if present.
    if (_repo.isAuthenticated) {
      state = state.copyWith(
        status: SessionStatus.authenticated,
        userId: _repo.currentUserId,
      );
    } else {
      state = state.copyWith(status: SessionStatus.unauthenticated);
    }

    // Listen for future auth changes (login / logout from Supabase).
    _repo.authStateStream?.listen((event) {
      final user = event.session?.user;
      if (user != null) {
        state = state.copyWith(
          status: SessionStatus.authenticated,
          userId: user.id,
        );
      } else {
        state = state.copyWith(
          status: SessionStatus.unauthenticated,
          userId: null,
        );
      }
    });
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  Future<AuthResult> signIn(String email, String password) async {
    final result = await _repo.signIn(email, password);
    if (result is AuthSuccess) {
      state = state.copyWith(
        status: result.isGuest
            ? SessionStatus.guest
            : SessionStatus.authenticated,
        userId: _repo.currentUserId,
      );
    }
    return result;
  }

  Future<AuthResult> signUp(String email, String password) async {
    final result = await _repo.signUp(email, password);
    if (result is AuthSuccess) {
      state = state.copyWith(
        status: result.isGuest
            ? SessionStatus.guest
            : SessionStatus.authenticated,
        userId: _repo.currentUserId,
      );
    }
    return result;
  }

  void continueAsGuest() {
    state = state.copyWith(status: SessionStatus.guest, userId: null);
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = state.copyWith(
      status: SessionStatus.unauthenticated,
      userId: null,
    );
  }
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier(ref.read(authRepositoryProvider));
});
