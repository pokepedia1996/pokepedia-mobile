import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/auth/presentation/signup_page.dart';
import 'package:pokepedia_mobile/features/auth/presentation/widgets/google_sign_in_button.dart';

/// Stands in for Supabase so registering can be driven without a network.
class _FakeAuth extends AuthNotifier {
  _FakeAuth({this.googleError});

  final String? googleError;

  /// False stands in for the user dismissing the account sheet.
  bool googleSignedIn = true;
  int googleCalls = 0;
  int signUpCalls = 0;

  @override
  Future<AppUser?> build() async => null;

  @override
  Future<SignUpResult> signUp(
    String username,
    String email,
    String password,
  ) async {
    signUpCalls++;
    return const SignUpResult(SignUpOutcome.needsEmailConfirmation);
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
  final router = GoRouter(
    initialLocation: '/signup',
    routes: [
      GoRoute(path: '/signup', builder: (_, __) => const SignupPage()),
      GoRoute(
        path: '/account',
        builder: (_, __) => const Scaffold(body: Text('Akun')),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('Masuk')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [authProvider.overrideWith(() => auth)],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

void main() {
  testWidgets('offers Google registration, labelled for signing up', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeAuth()));
    await tester.pumpAndSettle();

    expect(find.byType(SocialButtons), findsOneWidget);
    // The signup wording, not the login page's "Masuk dengan Google".
    expect(find.text('Daftar dengan Google'), findsOneWidget);
    expect(find.text('Masuk dengan Google'), findsNothing);
  });

  testWidgets('a successful Google registration lands on the account page', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_host(auth));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Daftar dengan Google'));
    await tester.pumpAndSettle();

    expect(auth.googleCalls, 1);
    // Straight in: Google has verified the address, so unlike the email form
    // there is no confirmation step to sit through.
    expect(find.text('Akun'), findsOneWidget);
    expect(auth.signUpCalls, 0);
  });

  testWidgets('backing out of the Google sheet reports nothing', (
    tester,
  ) async {
    final auth = _FakeAuth()..googleSignedIn = false;
    await tester.pumpWidget(_host(auth));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Daftar dengan Google'));
    await tester.pumpAndSettle();

    expect(auth.googleCalls, 1);
    expect(find.text('Akun'), findsNothing);
    expect(find.text('Daftar dengan Google'), findsOneWidget);
  });

  testWidgets('a Google failure is shown on the form', (tester) async {
    await tester.pumpWidget(
      _host(_FakeAuth(googleError: 'Unsupported provider: provider is not enabled')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Daftar dengan Google'));
    await tester.pumpAndSettle();

    expect(find.text('Akun'), findsNothing);
    // Rendered through the shared translation table, as the email path is.
    expect(
      find.textContaining('Google'),
      findsWidgets,
    );
  });
}
