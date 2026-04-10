/// test/widget_test.dart
///
/// Widget + unit tests covering:
///   1. AuthGate routing (login → home on guest skip)
///   2. Bottom nav picks correct tab
///   3. Home screen renders 3 dashboard components
///   4. WipPage renders required heading text
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:therapy_app/app.dart';
import 'package:therapy_app/features/auth/state/auth_provider.dart';
import 'package:therapy_app/features/auth/data/auth_repository.dart';
import 'package:therapy_app/shared/widgets/wip_page.dart';
import 'package:therapy_app/features/home/presentation/home_screen.dart';
import 'package:therapy_app/routing/app_scaffold.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthRepository extends Mock implements AuthRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer makeContainer({SessionStatus initialStatus = SessionStatus.unauthenticated}) {
  final container = ProviderContainer(
    overrides: [
      // Override session directly so we don't need real Supabase.
      sessionProvider.overrideWith(
        (ref) => _TestSessionNotifier(initialStatus),
      ),
    ],
  );
  return container;
}

class _TestSessionNotifier extends SessionNotifier {
  _TestSessionNotifier(this._status)
      : super(MockAuthRepository());

  final SessionStatus _status;

  @override
  Future<void> _init() async {
    // Skip real initialisation in tests.
    state = SessionState(status: _status);
  }
}

Widget wrapWithProviders(
  Widget child, {
  SessionStatus status = SessionStatus.unauthenticated,
}) {
  return ProviderScope(
    overrides: [
      sessionProvider.overrideWith(
        (ref) => _TestSessionNotifier(status),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

// ---------------------------------------------------------------------------
// 1. AuthGate routing
// ---------------------------------------------------------------------------

void main() {
  group('AuthGate', () {
    testWidgets('shows LoginScreen when unauthenticated', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(const AuthGate()),
      );
      await tester.pump();

      // LoginScreen has Sign In / Create Account segment.
      expect(find.text('Sign In'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows AppScaffold when guest session active', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          const AuthGate(),
          status: SessionStatus.guest,
        ),
      );
      await tester.pump();

      // AppScaffold renders bottom nav with Home label.
      expect(find.text('Home'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows AppScaffold when authenticated', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          const AuthGate(),
          status: SessionStatus.authenticated,
        ),
      );
      await tester.pump();

      expect(find.text('Home'), findsAtLeastNWidgets(1));
    });
  });

  // -------------------------------------------------------------------------
  // 2. Bottom nav tab switching
  // -------------------------------------------------------------------------

  group('AppScaffold bottom nav', () {
    testWidgets('starts on Home tab (index 2)', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          const AppScaffold(),
          status: SessionStatus.guest,
        ),
      );
      await tester.pump();

      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('tapping FSR Grip tab shows WIP page', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          const AppScaffold(),
          status: SessionStatus.guest,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('FSR Grip'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('FSR GRIP STRENGTH PAGE'),
        findsOneWidget,
      );
    });

    testWidgets('tapping PT Tracking tab shows WIP page', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          const AppScaffold(),
          status: SessionStatus.guest,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('PT Tracking'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('PHYSICAL THERAPY TRACKING'),
        findsOneWidget,
      );
    });

    testWidgets('tapping Pinch tab shows WIP page', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(
          const AppScaffold(),
          status: SessionStatus.guest,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Pinch'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('PINCH STRENGTH'),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  // 3. WipPage heading text
  // -------------------------------------------------------------------------

  group('WipPage', () {
    testWidgets('renders exact FSR heading', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WipPage(
            heading: 'FSR GRIP STRENGTH PAGE.\nWORK IN PROGRESS.',
            description: 'desc',
            icon: Icons.star,
          ),
        ),
      );
      expect(find.textContaining('FSR GRIP STRENGTH PAGE'), findsOneWidget);
      expect(find.textContaining('WORK IN PROGRESS'), findsOneWidget);
    });

    testWidgets('disabled Coming Soon button is present', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WipPage(
            heading: 'TEST',
            description: 'desc',
            icon: Icons.star,
          ),
        ),
      );
      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Coming Soon'),
      );
      expect(btn.onPressed, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 4. HomeScreen renders 3 dashboard components
  // -------------------------------------------------------------------------

  group('HomeScreen', () {
    testWidgets('renders streak, grip, and chart components', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(const HomeScreen(), status: SessionStatus.guest),
      );
      await tester.pump();

      // Streak card
      expect(find.text('Day Streak'), findsOneWidget);
      // Grip card
      expect(find.text('Grip Strength'), findsOneWidget);
      // Chart heading
      expect(find.text('Wrist Flexion Progress'), findsOneWidget);
    });

    testWidgets('guest mode shows sync banner', (tester) async {
      await tester.pumpWidget(
        wrapWithProviders(const HomeScreen(), status: SessionStatus.guest),
      );
      await tester.pump();

      expect(find.text('Sign in to sync your progress'), findsOneWidget);
    });
  });
}
