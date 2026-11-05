import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/features/onboarding/presentation/onboarding_page.dart';
import 'package:pokepedia_mobile/features/onboarding/usecase/onboarding_intents.dart';
import 'package:pokepedia_mobile/features/user/repository/user_repository.dart';
import 'package:pokepedia_mobile/features/user/usecase/user_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A new account's two steps: a username, then what they came to do, which
/// decides where they land and nothing else.
class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._user, {this.completeError});

  final AppUser? _user;
  final String? completeError;

  String? claimed;
  int completeCalls = 0;

  @override
  Future<AppUser?> build() async => _user;

  @override
  Future<String?> completeOnboarding(String username) async {
    completeCalls++;
    claimed = username;
    if (completeError != null) return completeError;
    // The real one reloads the profile onboarded, which takes the page down.
    state = AsyncData(
      AppUser(
        id: _user!.id,
        email: _user.email,
        username: username,
        onboarded: true,
      ),
    );
    return null;
  }
}

class _FakeUsers implements UserRepository {
  _FakeUsers({this.taken = const {}, this.unreachable = false});

  final Set<String> taken;

  /// Null is what the repository returns when the RPC could not be asked.
  final bool unreachable;

  final checked = <String>[];

  @override
  Future<bool?> isUsernameAvailable(String username) async {
    checked.add(username);
    if (unreachable) return null;
    return !taken.contains(username);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppUser _user({bool? onboarded}) =>
    AppUser(id: 'user-1', email: 'me@example.com', onboarded: onboarded);

/// What a test can look at after pumping.
class _Harness {
  _Harness(this.auth, this.users, this.container);

  final _FakeAuth auth;
  final _FakeUsers users;
  final ProviderContainer container;
  final landed = <String>[];
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required AppUser? user,
  String? completeError,
  _FakeUsers? users,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final auth = _FakeAuth(user, completeError: completeError);
  final fakeUsers = users ?? _FakeUsers();
  late _Harness harness;
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => auth),
      userRepositoryProvider.overrideWithValue(fakeUsers),
      onboardingLandingProvider.overrideWithValue(
        (route) => harness.landed.add(route),
      ),
    ],
  );
  addTearDown(container.dispose);
  harness = _Harness(auth, fakeUsers, container);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // Mounted through `builder`, as `PokepediaApp` does: above the
      // Navigator, and so outside the app's Overlay. Hosting it as `home:`
      // would hide the case where a TextField has no Overlay of its own.
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) =>
            OnboardingGate(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Center(child: Text('beranda'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  // Past the debounce, so the availability check has answered.
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String label) =>
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, label))
        .onPressed !=
    null;

Future<void> _toIntents(WidgetTester tester, {String name = 'mulyana'}) async {
  await _type(tester, name);
  await tester.tap(find.text('Lanjut'));
  await tester.pumpAndSettle();
}

Future<void> _tapOption(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<List<String>?> _storedIntents() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList('onboarding_intents:user-1');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the gate', () {
    testWidgets('stays shut for a user who has already onboarded', (
      tester,
    ) async {
      await _pump(tester, user: _user(onboarded: true));
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.text('beranda'), findsOneWidget);
    });

    testWidgets('stays shut while the profile row is in flight', (
      tester,
    ) async {
      await _pump(tester, user: _user());
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('stays shut for a guest', (tester) async {
      await _pump(tester, user: null);
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('opens on step one for an unfinished account', (tester) async {
      await _pump(tester, user: _user(onboarded: false));
      expect(find.text('Pilih'), findsOneWidget);
      expect(find.text('username kamu.'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
    });
  });

  group('step one: the username', () {
    testWidgets('the field takes a tap and typing', (tester) async {
      await _pump(tester, user: _user(onboarded: false));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a free name: the preview, the green hint, Lanjut', (
      tester,
    ) async {
      await _pump(tester, user: _user(onboarded: false));
      expect(_enabled(tester, 'Lanjut'), isFalse);

      await _type(tester, 'mulyana');
      expect(find.text('@mulyana'), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('Mantap, username ini tersedia!'), findsOneWidget);
      expect(_enabled(tester, 'Lanjut'), isTrue);
    });

    testWidgets('only what the database allows can be typed', (tester) async {
      await _pump(tester, user: _user(onboarded: false));
      await _type(tester, 'mul.ya-na!');
      expect(find.text('@mulyana'), findsOneWidget);

      await _type(tester, 'a' * 30);
      expect(find.text('@${'a' * 20}'), findsOneWidget);
    });

    testWidgets('too short is said without asking the server', (tester) async {
      final harness = await _pump(tester, user: _user(onboarded: false));
      await _type(tester, 'ab');
      expect(find.text('Minimal 3 karakter.'), findsOneWidget);
      expect(harness.users.checked, isEmpty);
      expect(_enabled(tester, 'Lanjut'), isFalse);
    });

    testWidgets('a taken name is said, and is never a way on', (tester) async {
      await _pump(
        tester,
        user: _user(onboarded: false),
        users: _FakeUsers(taken: {'mulyana'}),
      );
      await _type(tester, 'mulyana');
      expect(find.text('Username sudah dipakai'), findsOneWidget);
      expect(_enabled(tester, 'Lanjut'), isFalse);
    });

    testWidgets('a name that cannot be checked can still go on', (
      tester,
    ) async {
      await _pump(
        tester,
        user: _user(onboarded: false),
        users: _FakeUsers(unreachable: true),
      );
      await _type(tester, 'mulyana');
      expect(
        find.text('Tidak bisa memeriksa ketersediaan. Kamu tetap bisa lanjut.'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'Lanjut'), isTrue);
    });

    testWidgets('Lanjut claims nothing yet', (tester) async {
      final harness = await _pump(tester, user: _user(onboarded: false));
      await _toIntents(tester);
      expect(find.text('Mau ngapain'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      expect(harness.auth.completeCalls, 0);
    });
  });

  group('step two: what they came to do', () {
    testWidgets('every option starts unpicked', (tester) async {
      await _pump(tester, user: _user(onboarded: false));
      await _toIntents(tester);
      for (final intent in OnboardingIntent.values) {
        expect(find.text(intent.title), findsOneWidget);
      }
      final ticked = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.selected == true);
      expect(ticked, isEmpty);
    });

    testWidgets('back keeps the name, and it can be changed', (tester) async {
      final harness = await _pump(tester, user: _user(onboarded: false));
      await _toIntents(tester);
      await tester.tap(find.bySemanticsLabel('Kembali'));
      await tester.pumpAndSettle();

      expect(find.text('@mulyana'), findsOneWidget);
      await _toIntents(tester, name: 'mulyana_tcg');
      await _tapText(tester, 'Mulai jelajah');
      expect(harness.auth.claimed, 'mulyana_tcg');
    });

    testWidgets('lands on the first pick in list order, keeps them all', (
      tester,
    ) async {
      final harness = await _pump(tester, user: _user(onboarded: false));
      await _toIntents(tester);
      // Tapped out of order; the list's order decides.
      await _tapOption(tester, 'Jual kartu');
      await _tapOption(tester, 'Catat & pantau koleksi');
      await _tapText(tester, 'Mulai jelajah');

      expect(harness.auth.claimed, 'mulyana');
      expect(harness.landed, [Routes.portfolio]);
      expect(await _storedIntents(), ['collect', 'sell']);
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('each pick lands where the notes say', (tester) async {
      for (final (intent, route) in [
        (OnboardingIntent.buy, Routes.market),
        (OnboardingIntent.sell, Routes.seller),
        (OnboardingIntent.bid, Routes.market),
      ]) {
        SharedPreferences.setMockInitialValues({});
        final harness = await _pump(tester, user: _user(onboarded: false));
        await _toIntents(tester);
        await _tapOption(tester, intent.title);
        await _tapText(tester, 'Mulai jelajah');
        expect(harness.landed, [route], reason: intent.raw);
        // Bidding gets Market's note on what a WTB is; buying doesn't.
        expect(
          harness.container.read(marketWtbTipProvider),
          intent == OnboardingIntent.bid,
          reason: intent.raw,
        );
      }
    });

    testWidgets('nothing picked is Beranda', (tester) async {
      final harness = await _pump(tester, user: _user(onboarded: false));
      await _toIntents(tester);
      await _tapText(tester, 'Mulai jelajah');
      expect(harness.landed, [Routes.home]);
    });

    testWidgets('Lewati dulu: Beranda, and no intents', (tester) async {
      final harness = await _pump(tester, user: _user(onboarded: false));
      await _toIntents(tester);
      await _tapOption(tester, 'Jual kartu');
      await _tapText(tester, 'Lewati dulu');

      expect(harness.auth.claimed, 'mulyana');
      expect(harness.landed, [Routes.home]);
      expect(await _storedIntents(), isEmpty);
    });

    testWidgets('a name taken in the meantime goes back to step one', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        user: _user(onboarded: false),
        completeError: 'Username sudah dipakai',
      );
      await _toIntents(tester);
      await _tapText(tester, 'Mulai jelajah');

      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('Username sudah dipakai'), findsOneWidget);
      expect(harness.landed, isEmpty);
    });

    testWidgets('any other failure is said on step two', (tester) async {
      final harness = await _pump(
        tester,
        user: _user(onboarded: false),
        completeError: 'Waktu koneksi habis. Coba lagi.',
      );
      await _toIntents(tester);
      await _tapText(tester, 'Mulai jelajah');

      expect(find.text('Waktu koneksi habis. Coba lagi.'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      expect(harness.landed, isEmpty);
    });
  });

  group('suggested names', () {
    test('a base from a display name or an email', () {
      expect(usernameBase('Mulyana'), 'mulyana');
      expect(usernameBase('Budi Santoso'), 'budi_santoso');
      expect(usernameBase('ash.ketchum+tcg'), 'ash_ketchum_tcg');
      expect(usernameBase('__x__'), isNull);
      expect(usernameBase('a' * 30), 'a' * 20);
    });

    test('variations that fit the database rule', () {
      final names = usernameSuggestions('mulyana', year: 2026);
      expect(names, ['mulyana_tcg', 'mulyana_26', 'binder_mulyana']);

      final long = usernameSuggestions('a' * 20, year: 2026);
      for (final name in long) {
        expect(RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(name), isTrue);
      }
    });
  });
}
