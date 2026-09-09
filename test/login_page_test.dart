import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/core/utils/auth_errors.dart';
import 'package:pokepedia_mobile/features/auth/presentation/login_page.dart';
import 'package:pokepedia_mobile/features/auth/presentation/widgets/google_sign_in_button.dart';

/// Records what the page asked for, so the two-step flow can be driven
/// without touching Supabase.
class _FakeAuth extends AuthNotifier {
  _FakeAuth({this.googleError});

  final String? googleError;

  /// Whether the fake sheet reports a session — false stands in for the user
  /// backing out.
  bool googleSignedIn = true;
  int googleCalls = 0;
  (String, String)? passwordCall;

  @override
  Future<AppUser?> build() async => null;

  @override
  Future<String?> signIn(String email, String password) async {
    passwordCall = (email, password);
    return null;
  }

  @override
  Future<({bool signedIn, String? error})> signInWithGoogle() async {
    googleCalls++;
    return (
      signedIn: googleError == null && googleSignedIn,
      error: googleError,
    );
  }
}

Widget _host(_FakeAuth auth) {
  // A real router: signing in navigates, and `context.go` asserts without one.
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(
        path: '/account',
        builder: (_, __) => const Scaffold(body: Text('Akun')),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, __) => const Scaffold(body: Text('Daftar')),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const Scaffold(body: Text('Lupa')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [authProvider.overrideWith(() => auth)],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

void main() {
  testWidgets('asks for the email first, password only after', (tester) async {
    await tester.pumpWidget(_host(_FakeAuth()));
    await tester.pumpAndSettle();

    // Step one: email and Google, no password field yet.
    expect(find.widgetWithText(ElevatedButton, 'Lanjutkan'), findsOneWidget);
    expect(find.byType(SocialButtons), findsOneWidget);
    expect(find.text('Password'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'ash@pokepedia.id');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Lanjutkan'));
    await tester.pumpAndSettle();

    // Step two: password, with the email shown as an editable chip.
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('ash@pokepedia.id'), findsOneWidget);
    expect(find.text('Lupa password?'), findsOneWidget);
    expect(find.byType(SocialButtons), findsNothing);
  });

  testWidgets('refuses to advance on a malformed email', (tester) async {
    await tester.pumpWidget(_host(_FakeAuth()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Lanjutkan'));
    await tester.pumpAndSettle();

    expect(find.text('Email tidak valid'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('going back keeps the email that was typed', (tester) async {
    await tester.pumpWidget(_host(_FakeAuth()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ash@pokepedia.id');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Lanjutkan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Lanjutkan'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'ash@pokepedia.id',
    );
  });

  testWidgets('signs in with the address from step one', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_host(auth));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, ' ash@pokepedia.id ');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Lanjutkan'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'pikachu123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Masuk'));
    await tester.pumpAndSettle();

    // Trimmed, matching what the web sends.
    expect(auth.passwordCall, ('ash@pokepedia.id', 'pikachu123'));
    // ...and it lands on the account page.
    expect(find.text('Akun'), findsOneWidget);
  });

  testWidgets('a successful Google sign-in lands on the account page', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_host(auth));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pumpAndSettle();

    expect(auth.googleCalls, 1);
    expect(find.text('Akun'), findsOneWidget);
  });

  testWidgets('backing out of the Google sheet reports nothing', (
    tester,
  ) async {
    // Cancelling returns neither a session nor an error, and must not be
    // dressed up as a failure.
    final auth = _FakeAuth()..googleSignedIn = false;
    await tester.pumpWidget(_host(auth));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pumpAndSettle();

    expect(find.text('Akun'), findsNothing);
    // Still on the email step, no error shown.
    expect(find.widgetWithText(ElevatedButton, 'Lanjutkan'), findsOneWidget);
  });

  testWidgets('a disabled provider reads as a plain message', (tester) async {
    final auth = _FakeAuth(
      googleError: 'Unsupported provider: provider is not enabled',
    );
    await tester.pumpWidget(_host(auth));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Masuk dengan Google'));
    await tester.pumpAndSettle();

    expect(
      find.text('Login dengan Google belum tersedia. Coba masuk dengan email.'),
      findsOneWidget,
    );
    // Never the raw Supabase string.
    expect(find.textContaining('provider is not enabled'), findsNothing);
  });

  group('translateAuthError', () {
    test('covers the provider-disabled cases', () {
      expect(
        translateAuthError(
          'Unsupported provider: provider is not enabled',
          provider: 'Google',
        ),
        'Login dengan Google belum tersedia. Coba masuk dengan email.',
      );
      // The message used to say "Google" whatever the provider was, so an
      // Apple failure named the wrong one.
      expect(
        translateAuthError(
          'Unsupported provider: provider is not enabled',
          provider: 'Apple',
        ),
        'Login dengan Apple belum tersedia. Coba masuk dengan email.',
      );
      expect(
        translateAuthError('Unsupported provider: provider is not enabled'),
        'Login belum tersedia. Coba masuk dengan email.',
      );
      expect(
        translateAuthError('AuthorizationErrorCode.unknown, error 1000'),
        contains('iCloud'),
      );
      expect(
        translateAuthError('Invalid login credentials'),
        'Email atau password salah',
      );
    });
  });
}
