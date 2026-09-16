import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/auth/presentation/onboarding_modal.dart';
import 'package:pokepedia_mobile/features/user/repository/user_repository.dart';
import 'package:pokepedia_mobile/features/user/usecase/user_notifier.dart';

/// `handle_new_user` writes every profile with a null username, and neither
/// the signup form nor a Google/Apple sign-in asks for one. Without this
/// modal an account keeps falling back to its email local-part and has no
/// profile page to link to — which is what "Lihat profil" needs.
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
    // The real one invalidates itself and the profile comes back onboarded,
    // which is what takes the modal down.
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

  /// Null is what the repository returns when the RPC could not be asked —
  /// a stalled network, a timeout, a missing grant.
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

AppUser _user({bool? onboarded}) => AppUser(
  id: 'user-1',
  email: 'pudyastasatria@gmail.com',
  onboarded: onboarded,
);

Future<void> _pump(
  WidgetTester tester, {
  required AppUser? user,
  _FakeAuth? auth,
  _FakeUsers? users,
}) async {
  tester.view.physicalSize = const Size(1170, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => auth ?? _FakeAuth(user)),
        userRepositoryProvider.overrideWithValue(users ?? _FakeUsers()),
      ],
      // Mounted through `builder`, exactly as `PokepediaApp` does — which
      // puts the gate *above* the Navigator, and so outside the app's
      // Overlay. Hosting it as `home:` instead would hide that: the field
      // would inherit the route's Overlay and never exercise the case where
      // there isn't one.
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) =>
            OnboardingGate(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Center(child: Text('beranda'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Walks the three tutorial cards to reach the username step.
Future<void> _toUsernameStep(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('stays shut for a user who has already onboarded', (
    tester,
  ) async {
    await _pump(tester, user: _user(onboarded: true));
    expect(find.text('Selamat Datang!'), findsNothing);
    expect(find.text('beranda'), findsOneWidget);
  });

  testWidgets('stays shut while the profile row is still in flight', (
    tester,
  ) async {
    // `onboarded` is null until `profiles` lands. Treating that as false
    // would flash the modal over every launch.
    await _pump(tester, user: _user());
    expect(find.text('Selamat Datang!'), findsNothing);
  });

  testWidgets('stays shut for a guest', (tester) async {
    await _pump(tester, user: null);
    expect(find.text('Selamat Datang!'), findsNothing);
  });

  testWidgets('opens on the tutorial when onboarding is unfinished', (
    tester,
  ) async {
    await _pump(tester, user: _user(onboarded: false));
    expect(find.text('Selamat Datang!'), findsOneWidget);
    // The username is the last step, not the first.
    expect(find.text('Pilih Username'), findsNothing);
  });

  testWidgets('walks the tutorial and ends on the username step', (
    tester,
  ) async {
    await _pump(tester, user: _user(onboarded: false));

    expect(find.text('Selamat Datang!'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Jelajahi Ekspansi'), findsOneWidget);

    await tester.tap(find.text('Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Selamat Datang!'), findsOneWidget);

    await _toUsernameStep(tester);
    expect(find.text('Pilih Username'), findsOneWidget);
    expect(find.text('Lanjut'), findsNothing);
  });

  testWidgets('the username field can be tapped', (tester) async {
    // Tapping a text field builds its selection overlay, which needs an
    // Overlay in scope. The gate is mounted above the router's Navigator, so
    // it is outside the app's own — tapping here threw "No Overlay widget
    // found" until the gate started carrying one. `enterText` alone does not
    // reach this path, which is why it went unnoticed.
    await _pump(tester, user: _user(onboarded: false));
    await _toUsernameStep(tester);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects a malformed username without asking the server', (
    tester,
  ) async {
    final users = _FakeUsers();
    await _pump(tester, user: _user(onboarded: false), users: users);
    await _toUsernameStep(tester);

    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pumpAndSettle();

    expect(
      find.text('3–15 karakter, hanya huruf, angka, dan underscore'),
      findsOneWidget,
    );
    expect(users.checked, isEmpty);
  });

  testWidgets('reports a name that is already taken', (tester) async {
    final users = _FakeUsers(taken: {'pudyasta'});
    await _pump(tester, user: _user(onboarded: false), users: users);
    await _toUsernameStep(tester);

    await tester.enterText(find.byType(TextField), 'pudyasta');
    await tester.pumpAndSettle();

    expect(users.checked, ['pudyasta']);
    expect(find.text('Username sudah dipakai'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Mulai Jelajahi'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('claims an available name and closes', (tester) async {
    final auth = _FakeAuth(_user(onboarded: false));
    await _pump(tester, user: null, auth: auth);
    await _toUsernameStep(tester);

    await tester.enterText(find.byType(TextField), 'pudyasta');
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(ElevatedButton, 'Mulai Jelajahi');
    expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(auth.completeCalls, 1);
    expect(auth.claimed, 'pudyasta');
    // The profile comes back onboarded, so the gate takes the modal down and
    // hands the app back.
    expect(find.text('Pilih Username'), findsNothing);
    expect(find.text('beranda'), findsOneWidget);
  });

  testWidgets('a name taken between the check and the submit is reported', (
    tester,
  ) async {
    // The debounced check can go stale; the unique index has the final say.
    final auth = _FakeAuth(
      _user(onboarded: false),
      completeError: 'Username sudah dipakai',
    );
    await _pump(tester, user: null, auth: auth);
    await _toUsernameStep(tester);

    await tester.enterText(find.byType(TextField), 'pudyasta');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mulai Jelajahi'));
    await tester.pumpAndSettle();

    expect(find.text('Username sudah dipakai'), findsOneWidget);
    expect(find.text('Pilih Username'), findsOneWidget);
  });

  testWidgets('a name that cannot be checked is still submittable', (
    tester,
  ) async {
    // The modal cannot be dismissed, so refusing to let an unverifiable name
    // through would lock the user out of the app entirely. The unique index
    // is the real authority, and `completeOnboarding` reports its verdict.
    final auth = _FakeAuth(_user(onboarded: false));
    await _pump(
      tester,
      user: null,
      auth: auth,
      users: _FakeUsers(unreachable: true),
    );
    await _toUsernameStep(tester);

    await tester.enterText(find.byType(TextField), 'pudyasta');
    await tester.pumpAndSettle();

    expect(
      find.text('Tidak bisa memeriksa ketersediaan. Kamu tetap bisa lanjut.'),
      findsOneWidget,
    );
    final submit = find.widgetWithText(ElevatedButton, 'Mulai Jelajahi');
    expect(tester.widget<ElevatedButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(auth.claimed, 'pudyasta');
  });

  testWidgets('a taken name is never submittable', (tester) async {
    // Unlike an unverifiable one: here the server did answer.
    await _pump(
      tester,
      user: _user(onboarded: false),
      users: _FakeUsers(taken: {'pudyasta'}),
    );
    await _toUsernameStep(tester);

    await tester.enterText(find.byType(TextField), 'pudyasta');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Mulai Jelajahi'),
          )
          .onPressed,
      isNull,
    );
  });
}
