import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/onboarding/presentation/intro/intro_page.dart';
import 'package:pokepedia_mobile/features/onboarding/usecase/intro_flag.dart';
import 'package:pokepedia_mobile/shared/widgets/scribble_drawing.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth({
    this.googleSignedIn = true,
    this.googleError,
    this.googleThrows = false,
  });

  final bool googleThrows;
  final bool googleSignedIn;
  final String? googleError;
  int googleCalls = 0;

  @override
  Future<AppUser?> build() async => null;

  @override
  Future<({bool signedIn, String? error})> signInWithGoogle() async {
    googleCalls++;
    if (googleThrows) throw StateError('sheet blew up');
    return (signedIn: googleSignedIn, error: googleError);
  }
}

Future<_FakeAuth> _pump(
  WidgetTester tester, {
  _FakeAuth? auth,
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final fake = auth ?? _FakeAuth();
  final router = GoRouter(
    initialLocation: Routes.welcome,
    routes: [
      GoRoute(path: Routes.welcome, builder: (_, __) => const IntroPage()),
      GoRoute(
        path: Routes.home,
        builder: (_, __) => const Scaffold(body: Text('beranda')),
      ),
      GoRoute(
        path: Routes.signup,
        builder: (_, __) => const Scaffold(body: Text('halaman daftar')),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, __) => const Scaffold(body: Text('halaman masuk')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(() => fake)],
      child: MaterialApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  return fake;
}

Future<void> _next(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    IntroFlag.done.value = false;
  });
  tearDown(() {
    IntroFlag.done.value = true;
  });

  group('the slides', () {
    testWidgets('open on the welcome, with no way back or skip', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Halo,'), findsOneWidget);
      expect(find.text('kolektor!'), findsOneWidget);
      expect(find.text('Kenalan dulu, yuk'), findsOneWidget);
      expect(find.text('Lewati'), findsOneWidget);
      // Present but invisible: it takes no taps on the welcome.
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        0,
      );
    });

    testWidgets('the CTA walks the five features, then Daftar', (tester) async {
      await _pump(tester);
      await _next(tester, 'Kenalan dulu, yuk');
      expect(find.text('Scan kartu,'), findsOneWidget);
      expect(find.text('fitur 1 dari 5'), findsOneWidget);
      await _next(tester, 'Lanjut');
      expect(find.text('harga pasar'), findsOneWidget);
      await _next(tester, 'Lanjut');
      expect(find.text('siap tanding'), findsOneWidget);
      await _next(tester, 'Lanjut');
      expect(find.text('atau tawar'), findsOneWidget);
      await _next(tester, 'Lanjut');
      expect(find.text('kartu diterima'), findsOneWidget);
      expect(find.text('Mulai sekarang'), findsOneWidget);
      await _next(tester, 'Mulai sekarang');
      expect(find.text('Bikin akun, yuk!'), findsOneWidget);
    });

    testWidgets('a swipe moves between slides', (tester) async {
      await _pump(tester);
      await tester.fling(find.text('Halo,'), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Scan kartu,'), findsOneWidget);
      await tester.fling(find.text('Scan kartu,'), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Halo,'), findsOneWidget);
    });

    testWidgets('Lewati jumps to Daftar', (tester) async {
      await _pump(tester);
      await _next(tester, 'Kenalan dulu, yuk');
      await _next(tester, 'Lewati');
      expect(find.text('Bikin akun, yuk!'), findsOneWidget);
    });

    testWidgets('back goes to the slide before', (tester) async {
      await _pump(tester);
      await _next(tester, 'Kenalan dulu, yuk');
      await tester.tap(find.bySemanticsLabel('Kembali'));
      await tester.pumpAndSettle();
      expect(find.text('Halo,'), findsOneWidget);
    });
  });

  group('Daftar', () {
    Future<void> toDaftar(WidgetTester tester) async {
      await _next(tester, 'Kenalan dulu, yuk');
      await _next(tester, 'Lewati');
    }

    testWidgets('has no Masuk or guest door before it', (tester) async {
      await _pump(tester);
      expect(find.text('Masuk'), findsNothing);
      expect(find.text('Lihat-lihat dulu'), findsNothing);
    });

    testWidgets('Lihat-lihat dulu: marks the intro done and opens Beranda', (
      tester,
    ) async {
      await _pump(tester);
      await toDaftar(tester);
      await tester.tap(find.text('Lihat-lihat dulu'));
      await tester.pumpAndSettle();
      expect(find.text('beranda'), findsOneWidget);
      expect(IntroFlag.done.value, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'pokepedia.intro-seen.v1',
        ),
        isTrue,
      );
    });

    testWidgets('Daftar pakai email opens signup and marks done', (
      tester,
    ) async {
      await _pump(tester);
      await toDaftar(tester);
      await tester.tap(find.text('Daftar pakai email'));
      await tester.pumpAndSettle();
      expect(find.text('halaman daftar'), findsOneWidget);
      expect(IntroFlag.done.value, isTrue);
    });

    testWidgets('Masuk opens login and marks done', (tester) async {
      await _pump(tester);
      await toDaftar(tester);
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      expect(find.text('halaman masuk'), findsOneWidget);
      expect(IntroFlag.done.value, isTrue);
    });

    testWidgets('Google signed in: marks done and goes to Beranda', (
      tester,
    ) async {
      final auth = await _pump(tester);
      await toDaftar(tester);
      await tester.tap(find.text('Lanjut dengan Google'));
      await tester.pumpAndSettle();
      expect(auth.googleCalls, 1);
      expect(find.text('beranda'), findsOneWidget);
      expect(IntroFlag.done.value, isTrue);
    });

    testWidgets('a cancelled Google sheet stays here, silently', (
      tester,
    ) async {
      await _pump(tester, auth: _FakeAuth(googleSignedIn: false));
      await toDaftar(tester);
      await tester.tap(find.text('Lanjut dengan Google'));
      await tester.pumpAndSettle();
      expect(find.text('Bikin akun, yuk!'), findsOneWidget);
      expect(IntroFlag.done.value, isFalse);
    });

    testWidgets('a Google failure is said, and the intro stays open', (
      tester,
    ) async {
      await _pump(
        tester,
        auth: _FakeAuth(googleSignedIn: false, googleError: 'network error'),
      );
      await toDaftar(tester);
      await tester.tap(find.text('Lanjut dengan Google'));
      await tester.pumpAndSettle();
      expect(find.text('Bikin akun, yuk!'), findsOneWidget);
      expect(IntroFlag.done.value, isFalse);
      expect(find.textContaining('Google'), findsWidgets);
    });

    testWidgets('a sign-in that throws frees the buttons again', (
      tester,
    ) async {
      final auth = _FakeAuth(googleThrows: true);
      await _pump(tester, auth: auth);
      await toDaftar(tester);
      await tester.tap(find.text('Lanjut dengan Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut dengan Google'));
      await tester.pumpAndSettle();
      expect(auth.googleCalls, 2);
    });

    testWidgets('Apple is not offered off iOS', (tester) async {
      await _pump(tester);
      await toDaftar(tester);
      expect(find.text('Lanjut dengan Apple'), findsNothing);
    });

    testWidgets('Apple is offered on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _pump(tester);
        await toDaftar(tester);
        expect(find.text('Lanjut dengan Apple'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('dark mode', () {
    testWidgets('the intro keeps its light ink on the cream paper', (
      tester,
    ) async {
      await _pump(tester, themeMode: ThemeMode.dark);
      // The page reads its palette inside the locked light theme, so the
      // dark device palette's pale ink never reaches the cream paper.
      final headline = tester.widget<Text>(find.text('Halo,'));
      expect(headline.style!.color!.computeLuminance(), lessThan(0.2));
    });
  });

  group('pokepad.pen geometry', () {
    // "Onboarding Baru 1 · Scan & Koleksi", 430×932: every number below is
    // read off that frame (absolute = frame position + parent offsets).
    testWidgets('slide 1 sits where the design puts it', (tester) async {
      await _pump(tester, size: const Size(430, 932));
      await tester.tap(find.text('Kenalan dulu, yuk'));
      await tester.pump();
      // Past the change (about 810 ms); not settled, as the drawings loop.
      await tester.pump(const Duration(milliseconds: 1500));

      Rect rect(Finder f) => tester.getRect(f.first);
      final art = rect(
        find.ancestor(
          of: find.byType(ScribbleDrawing),
          matching: find.byType(SizedBox),
        ),
      );
      expect(art, const Rect.fromLTWH(45, 214, 340, 300));

      final cta = rect(
        find.ancestor(
          of: find.text('Lanjut'),
          matching: find.byType(Container),
        ),
      );
      expect(cta, const Rect.fromLTWH(24, 848, 382, 54));

      final back = rect(find.byIcon(LucideIcons.arrowLeft));
      expect(back.center, const Offset(24 + 18, 56 + 18));
      expect(rect(find.byType(Image)).topLeft, const Offset(70, 60));
      expect(rect(find.byType(Image)).size, const Size(128, 28));
    });
  });

  group('pokepad.pen geometry · Daftar', () {
    testWidgets('Daftar sits where "Onboarding Baru 6" puts it', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _pump(tester, size: const Size(430, 932));
        await tester.tap(find.text('Kenalan dulu, yuk'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1500));
        await tester.tap(find.text('Lewati'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 2500));

        Rect rect(Finder f) => tester.getRect(f.first);
        Rect button(String label) => rect(
          find.ancestor(of: find.text(label), matching: find.byType(SizedBox)),
        );
        final art = rect(
          find.ancestor(
            of: find.byType(ScribbleDrawing),
            matching: find.byType(SizedBox),
          ),
        );
        // The drawing is the design's 236×208, centred.
        expect(art.size, const Size(236, 208));
        expect(art.center.dx, 215);
        // The three buttons are 52 tall with 10 between, as in "Tombol".
        final google = button('Lanjut dengan Google');
        final apple = button('Lanjut dengan Apple');
        final email = button('Daftar pakai email');
        expect([google.height, apple.height, email.height], [52, 52, 52]);
        expect(apple.top - google.top, 62);
        expect(email.top - apple.top, 62);
        // Then the buttons' 12 and the links' 14 before "Sudah punya akun?".
        expect(
          rect(find.text('Sudah punya akun?')).top - email.bottom,
          greaterThanOrEqualTo(26),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('introRedirect', () {
    test('signed out, not seen, on Beranda: to the welcome', () {
      expect(
        introRedirect(loggedIn: false, introDone: false, location: Routes.home),
        Routes.welcome,
      );
    });

    test('already seen: left alone', () {
      expect(
        introRedirect(loggedIn: false, introDone: true, location: Routes.home),
        isNull,
      );
    });

    test('signed in: never the intro, and the intro goes to Beranda', () {
      expect(
        introRedirect(loggedIn: true, introDone: false, location: Routes.home),
        isNull,
      );
      expect(
        introRedirect(
          loggedIn: true,
          introDone: false,
          location: Routes.welcome,
        ),
        Routes.home,
      );
    });

    test('a deep link is never turned aside', () {
      for (final location in [
        Routes.authConfirm,
        Routes.resetPassword,
        Routes.login,
        '/pack/abc',
      ]) {
        expect(
          introRedirect(loggedIn: false, introDone: false, location: location),
          isNull,
          reason: location,
        );
      }
    });
  });

  group('IntroFlag', () {
    test('unset in storage means not seen', () async {
      SharedPreferences.setMockInitialValues({});
      await IntroFlag.load();
      expect(IntroFlag.done.value, isFalse);
    });

    test('a stored true means seen', () async {
      SharedPreferences.setMockInitialValues({'pokepedia.intro-seen.v1': true});
      await IntroFlag.load();
      expect(IntroFlag.done.value, isTrue);
    });

    test('markDone survives a reload', () async {
      SharedPreferences.setMockInitialValues({});
      await IntroFlag.markDone();
      IntroFlag.done.value = false;
      await IntroFlag.load();
      expect(IntroFlag.done.value, isTrue);
    });
  });
}
