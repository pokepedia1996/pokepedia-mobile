import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/features/onboarding/presentation/onb_widgets.dart';
import 'package:pokepedia_mobile/features/onboarding/presentation/onboarding_page.dart';
import 'package:pokepedia_mobile/features/onboarding/usecase/onboarding_intents.dart';
import 'package:pokepedia_mobile/features/referral/repository/referral_repository.dart';
import 'package:pokepedia_mobile/features/referral/usecase/pending_referral.dart';
import 'package:pokepedia_mobile/features/referral/usecase/referral_providers.dart';
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
  List<String>? sentIntents;
  int completeCalls = 0;

  @override
  Future<AppUser?> build() async => _user;

  @override
  Future<String?> completeOnboarding(
    String username, {
    List<String> intents = const [],
  }) async {
    completeCalls++;
    claimed = username;
    sentIntents = intents;
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

/// `validate_referral_code` / `apply_referral_code`, answering from [checks].
class _FakeReferral implements ReferralRepository {
  _FakeReferral({
    this.checks = const {},
    this.applyOk = true,
    this.applyThrows = false,
    this.validateThrows = false,
    this.validateDelay = Duration.zero,
  });

  final Map<String, ReferralCheck> checks;
  final bool applyOk;
  final bool applyThrows;
  final bool validateThrows;
  final Duration validateDelay;

  final validated = <String>[];
  final applied = <String>[];

  @override
  Future<ReferralCheck> validateCode(String code) async {
    validated.add(code);
    if (validateDelay > Duration.zero) await Future.delayed(validateDelay);
    if (validateThrows) throw const ReferralException('boom');
    return checks[code] ??
        const ReferralCheck(valid: false, reason: 'not_found');
  }

  @override
  Future<ReferralApplyResult> applyCode(String code) async {
    applied.add(code);
    if (applyThrows) throw const ReferralException('boom');
    return ReferralApplyResult(ok: applyOk);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  _FakeReferral? referral,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final auth = _FakeAuth(user, completeError: completeError);
  final fakeUsers = users ?? _FakeUsers();
  late _Harness harness;
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => auth),
      userRepositoryProvider.overrideWithValue(fakeUsers),
      referralRepositoryProvider.overrideWithValue(referral ?? _FakeReferral()),
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
  await tester.enterText(find.byType(TextField).first, text);
  // Past the debounce, so the availability check has answered.
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<OnbCta>(find.widgetWithText(OnbCta, label)).onTap != null;

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
      await tester.tap(find.byType(TextField).first);
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

    testWidgets('a character the database refuses is said, not dropped', (
      tester,
    ) async {
      await _pump(tester, user: _user(onboarded: false));
      await _type(tester, 'mul.ya-na!');
      expect(find.text('@mul.ya-na!'), findsOneWidget);
      expect(
        find.text('Cuma boleh huruf, angka, dan garis bawah.'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'Lanjut'), isFalse);
      await _type(tester, 'mul ya na');
      expect(find.text('@mulyana'), findsOneWidget);
      expect(_enabled(tester, 'Lanjut'), isTrue);

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
      expect(
        find.text('Yah, sudah dipakai. Coba saran di bawah.'),
        findsOneWidget,
      );
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
      expect(harness.auth.sentIntents, ['collect', 'sell']);
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
      expect(harness.auth.sentIntents, isEmpty);
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
      expect(
        find.text('Yah, sudah dipakai. Coba saran di bawah.'),
        findsOneWidget,
      );
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

  group('pokepad.pen geometry', () {
    // "Onboarding Baru 7" and "8", 430×932: absolute = frame offsets added
    // up (top 56, sides 24, Isi from 92).
    Rect rect(WidgetTester t, Finder f) => t.getRect(f.first);

    testWidgets('step 1 sits where the design puts it', (tester) async {
      await _pump(
        tester,
        user: _user(onboarded: false),
        size: const Size(430, 932),
      );
      await _type(tester, 'mulyana');

      expect(
        rect(tester, find.byIcon(LucideIcons.arrowLeft)).center,
        const Offset(42, 74),
      );
      // The two 44×8 segments, 6 apart, centred on the 382 column.
      final segs = find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 44,
      );
      expect(tester.getRect(segs.at(0)), const Rect.fromLTWH(168, 70, 44, 8));
      expect(tester.getRect(segs.at(1)), const Rect.fromLTWH(218, 70, 44, 8));

      // Below the copy block the design stacks 18 apart (the copy's own
      // height depends on the font, so it is measured, not assumed).
      final subBottom = rect(
        tester,
        find.textContaining('Ini nama profilmu'),
      ).bottom;
      final preview = tester.getRect(
        find
            .ancestor(
              of: find.text('pratinjau profilmu'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(preview.size, const Size(382, 76));
      expect(preview.left, 24);
      expect(preview.top, closeTo(subBottom + 18, 1));

      // Username field: 382×54, its label 16 + 8 above it, 18 under the card.
      final field = tester.getRect(
        find
            .ancestor(
              of: find.byType(TextField).first,
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(field.size, const Size(382, 54));
      expect(field.top, closeTo(preview.bottom + 18 + 16 + 8, 1));

      // Footer: the CTA 382×54 with the legal line 12 under it.
      final cta = tester.getRect(find.widgetWithText(OnbCta, 'Lanjut'));
      final legal = tester.getRect(find.textContaining('karakter: huruf'));
      expect(cta.size, const Size(382, 54));
      expect(cta.left, 24);
      expect(legal.top, closeTo(cta.bottom + 12, 1));
      // The page ends 28 above the bottom edge.
      expect(legal.bottom, closeTo(932 - 28, 1));
    });

    testWidgets('step 2 sits where the design puts it', (tester) async {
      await _pump(
        tester,
        user: _user(onboarded: false),
        size: const Size(430, 932),
      );
      await _toIntents(tester);

      // Four options, each 382×80, 12 apart, the first 18 + 4 under the
      // copy.
      final titles = [
        'Catat & pantau koleksi',
        'Cari & beli kartu',
        'Jual kartu',
        'Tawar kartu incaran',
      ];
      final subBottom = tester
          .getRect(find.textContaining('Pilih satu atau lebih'))
          .bottom;
      for (var i = 0; i < 4; i++) {
        final box = tester.getRect(
          find
              .ancestor(
                of: find.text(titles[i]),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        expect(box.size, const Size(382, 80), reason: titles[i]);
        expect(
          box.top,
          closeTo(subBottom + 18 + 4 + i * 92, 1),
          reason: titles[i],
        );
        expect(box.left, 24);
      }
      expect(
        tester.getRect(find.widgetWithText(OnbCta, 'Mulai jelajah')).top,
        821,
      );
    });
  });

  group('the push between steps', () {
    testWidgets('the new page slides in from the right over 560 ms', (
      tester,
    ) async {
      await _pump(tester, user: _user(onboarded: false));
      await _type(tester, 'mulyana');
      await tester.tap(find.text('Lanjut'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-push both pages are on screen, the new one still on its way in
      // from the right.
      expect(find.text('Mau ngapain'), findsOneWidget);
      expect(tester.getRect(find.text('Mau ngapain')).left, greaterThan(100));
      expect(find.text('Pilih'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Pilih'), findsNothing);
      expect(tester.getRect(find.text('Mau ngapain')).left, 24);
    });
  });

  group('step one: the referral code', () {
    const valid = ReferralCheck(valid: true, referrerUsername: 'satoshi');

    Future<void> typeCode(WidgetTester tester, String code) async {
      await tester.enterText(find.byType(TextField).last, code);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
    }

    testWidgets('is optional: nothing typed, nothing asked', (tester) async {
      final referral = _FakeReferral();
      await _pump(tester, user: _user(onboarded: false), referral: referral);
      await _toIntents(tester);
      expect(find.text('Mau ngapain'), findsOneWidget);
      expect(referral.validated, isEmpty);
      expect(referral.applied, isEmpty);
    });

    testWidgets('only a code with the right shape is asked about', (
      tester,
    ) async {
      final referral = _FakeReferral();
      await _pump(tester, user: _user(onboarded: false), referral: referral);
      await typeCode(tester, 'ab');
      expect(referral.validated, isEmpty);
    });

    testWidgets('an invite link fills the field and is checked', (
      tester,
    ) async {
      await PendingReferral.save('SATOS728');
      addTearDown(PendingReferral.clear);
      final referral = _FakeReferral(checks: {'SATOS728': valid});
      await _pump(tester, user: _user(onboarded: false), referral: referral);
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(referral.validated, ['SATOS728']);
      expect(find.text('Diajak @satoshi 🎉'), findsOneWidget);
    });

    testWidgets('a good code shows who invited, in upper case', (tester) async {
      final referral = _FakeReferral(checks: {'SATOS728': valid});
      await _pump(tester, user: _user(onboarded: false), referral: referral);
      await typeCode(tester, 'satos728');
      expect(referral.validated, ['SATOS728']);
      expect(find.text('Diajak @satoshi 🎉'), findsOneWidget);
      expect(
        find.text('Kamu dapat kupon Gratis Ongkir begitu akunmu jadi.'),
        findsOneWidget,
      );
    });

    testWidgets('an unknown code is said, and the card stays away', (
      tester,
    ) async {
      await _pump(tester, user: _user(onboarded: false));
      await typeCode(tester, 'NOPE123');
      expect(find.text('Kodenya nggak ketemu. Cek lagi, ya.'), findsOneWidget);
      expect(find.textContaining('Diajak'), findsNothing);
    });

    testWidgets('your own code is said', (tester) async {
      final referral = _FakeReferral(
        checks: {
          'MULYA123': const ReferralCheck(valid: false, reason: 'own_code'),
        },
      );
      await _pump(tester, user: _user(onboarded: false), referral: referral);
      await typeCode(tester, 'MULYA123');
      expect(find.text('Itu kode kamu sendiri.'), findsOneWidget);
    });

    testWidgets('a failed check stays quiet and does not block', (
      tester,
    ) async {
      await _pump(
        tester,
        user: _user(onboarded: false),
        referral: _FakeReferral(validateThrows: true),
      );
      await _type(tester, 'mulyana');
      await typeCode(tester, 'SATOS728');
      expect(find.textContaining('Diajak'), findsNothing);
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(find.text('Mau ngapain'), findsOneWidget);
    });

    testWidgets('Lanjut applies a valid code once, even after back', (
      tester,
    ) async {
      final referral = _FakeReferral(checks: {'SATOS728': valid});
      await _pump(tester, user: _user(onboarded: false), referral: referral);
      await _type(tester, 'mulyana');
      await typeCode(tester, 'SATOS728');
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(referral.applied, ['SATOS728']);

      await tester.tap(find.byIcon(LucideIcons.arrowLeft));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(referral.applied, ['SATOS728']);
    });

    testWidgets('a code that will not apply says so and still goes on', (
      tester,
    ) async {
      final referral = _FakeReferral(
        checks: {'SATOS728': valid},
        applyOk: false,
      );
      await _pump(tester, user: _user(onboarded: false), referral: referral);
      await _type(tester, 'mulyana');
      await typeCode(tester, 'SATOS728');
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(find.text('Kode referal tidak bisa dipakai'), findsWidgets);
      expect(find.text('Mau ngapain'), findsOneWidget);
    });

    testWidgets('Lanjut tapped before the check answers still applies it', (
      tester,
    ) async {
      final referral = _FakeReferral(checks: {'SATOS728': valid});
      await _pump(tester, user: _user(onboarded: false), referral: referral);
      await _type(tester, 'mulyana');
      // Typed, then Lanjut at once: the debounce has not even fired.
      await tester.enterText(find.byType(TextField).last, 'SATOS728');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(referral.applied, ['SATOS728']);
      expect(find.text('Mau ngapain'), findsOneWidget);
    });

    testWidgets('Lanjut while the check is in flight waits, not asks again', (
      tester,
    ) async {
      final referral = _FakeReferral(
        checks: {'SATOS728': valid},
        validateDelay: const Duration(seconds: 1),
      );
      await _pump(tester, user: _user(onboarded: false), referral: referral);
      await _type(tester, 'mulyana');
      await tester.enterText(find.byType(TextField).last, 'SATOS728');
      // Past the debounce, before the answer.
      await tester.pump(const Duration(milliseconds: 500));
      expect(referral.validated, ['SATOS728']);
      await tester.tap(find.text('Lanjut'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(referral.validated, ['SATOS728']);
      expect(referral.applied, ['SATOS728']);
    });

    testWidgets('an apply that throws still goes on', (tester) async {
      final referral = _FakeReferral(
        checks: {'SATOS728': valid},
        applyThrows: true,
      );
      await _pump(tester, user: _user(onboarded: false), referral: referral);
      await _type(tester, 'mulyana');
      await typeCode(tester, 'SATOS728');
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(find.text('Mau ngapain'), findsOneWidget);
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
