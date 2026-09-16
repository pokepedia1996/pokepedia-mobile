import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/auth/presentation/signup_page.dart';

/// The registration page follows `app/signup/page.tsx`: email, then password,
/// then a screen telling you to go and open the confirmation link. It used to
/// ask for everything at once — and for a username the web never collects.
class _FakeAuth extends AuthNotifier {
  _FakeAuth({this.outcome = SignUpOutcome.needsEmailConfirmation});

  final SignUpOutcome outcome;
  int signUpCalls = 0;
  String? signUpEmail;
  String? signUpPassword;

  @override
  Future<AppUser?> build() async => null;

  @override
  Future<SignUpResult> signUp(String email, String password) async {
    signUpCalls++;
    signUpEmail = email;
    signUpPassword = password;
    return SignUpResult(
      outcome,
      errorMessage: outcome == SignUpOutcome.error
          ? 'email rate limit exceeded'
          : null,
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
        builder: (_, __) => const Scaffold(body: Text('Halaman masuk')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [authProvider.overrideWith(() => auth)],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

Future<void> _toPasswordStep(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextField).first, email);
  await tester.tap(find.text('Lanjutkan'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('asks for the email first, password only after', (tester) async {
    await tester.pumpWidget(_host(_FakeAuth()));
    await tester.pumpAndSettle();

    expect(find.text('Buat Akun'), findsOneWidget);
    expect(find.text('Lanjutkan'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
    expect(find.text('Daftar'), findsNothing);

    await _toPasswordStep(tester, 'ash@pokepedia.id');

    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Daftar'), findsOneWidget);
    expect(find.text('Lanjutkan'), findsNothing);
  });

  testWidgets('never asks for a username, as the web does not', (tester) async {
    await tester.pumpWidget(_host(_FakeAuth()));
    await tester.pumpAndSettle();
    expect(find.text('Username'), findsNothing);

    await _toPasswordStep(tester, 'ash@pokepedia.id');
    expect(find.text('Username'), findsNothing);
  });

  testWidgets('refuses to advance on a malformed email', (tester) async {
    await tester.pumpWidget(_host(_FakeAuth()));
    await tester.pumpAndSettle();

    await _toPasswordStep(tester, 'ash-at-pokepedia');

    expect(find.text('Masukkan alamat email yang valid'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('going back keeps the email that was typed', (tester) async {
    await tester.pumpWidget(_host(_FakeAuth()));
    await tester.pumpAndSettle();
    await _toPasswordStep(tester, 'ash@pokepedia.id');

    // The chip doubles as the way back, as on the web.
    expect(find.text('ash@pokepedia.id'), findsOneWidget);
    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();

    expect(find.text('Lanjutkan'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'ash@pokepedia.id',
    );
  });

  testWidgets('holds "Daftar" until the password is long enough', (
    tester,
  ) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_host(auth));
    await tester.pumpAndSettle();
    await _toPasswordStep(tester, 'ash@pokepedia.id');

    ElevatedButton submit() => tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Daftar'),
    );

    expect(submit().onPressed, isNull);
    expect(find.text('Minimal 8 karakter'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'short');
    await tester.pumpAndSettle();
    expect(submit().onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'pikachu123');
    await tester.pumpAndSettle();
    expect(submit().onPressed, isNotNull);
  });

  testWidgets('registers with the address from step one, then says to check '
      'the inbox', (tester) async {
    final auth = _FakeAuth();
    await tester.pumpWidget(_host(auth));
    await tester.pumpAndSettle();
    await _toPasswordStep(tester, 'ash@pokepedia.id');

    await tester.enterText(find.byType(TextField).last, 'pikachu123');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daftar'));
    await tester.pumpAndSettle();

    expect(auth.signUpCalls, 1);
    expect(auth.signUpEmail, 'ash@pokepedia.id');
    expect(auth.signUpPassword, 'pikachu123');

    // The address is repeated back so a typo is caught here rather than by a
    // link that never arrives.
    expect(find.text('Cek Email Kamu'), findsOneWidget);
    expect(find.text('ash@pokepedia.id'), findsOneWidget);

    await tester.tap(find.text('Kembali ke halaman login'));
    await tester.pumpAndSettle();
    expect(find.text('Halaman masuk'), findsOneWidget);
  });

  testWidgets('a rejected sign-up stays on the password step, translated', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeAuth(outcome: SignUpOutcome.error)));
    await tester.pumpAndSettle();
    await _toPasswordStep(tester, 'ash@pokepedia.id');

    await tester.enterText(find.byType(TextField).last, 'pikachu123');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daftar'));
    await tester.pumpAndSettle();

    expect(find.text('Cek Email Kamu'), findsNothing);
    expect(
      find.text('Terlalu banyak percobaan. Coba lagi dalam beberapa menit.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the terms consent line before registering', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeAuth()));
    await tester.pumpAndSettle();
    await _toPasswordStep(tester, 'ash@pokepedia.id');

    expect(find.textContaining('Dengan mendaftar'), findsOneWidget);
    expect(find.textContaining('Syarat & Ketentuan'), findsOneWidget);
    expect(find.textContaining('Kebijakan Privasi'), findsOneWidget);
  });
}
