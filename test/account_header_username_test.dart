import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/core/utils/formatters.dart';
import 'package:pokepedia_mobile/features/account/presentation/account_page.dart';
import 'package:pokepedia_mobile/features/wallet/usecase/wallet_notifier.dart';
import 'package:pokepedia_mobile/shared/widgets/shimmer_box.dart';

/// The account header names the user by their `profiles.username`. It used to
/// fall back to the email's local part, which reads as a username without
/// being one — and puts part of the address on a screen someone may well be
/// showing to a seller they are trading with.
class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._user);
  final AppUser? _user;

  @override
  Future<AppUser?> build() async => _user;
}

const _email = 'tajirsadiq.biz@example.com';

Widget _host(AppUser? user, {Future<int>? balance}) {
  final router = GoRouter(
    initialLocation: Routes.account,
    routes: [
      GoRoute(path: Routes.account, builder: (_, __) => const AccountPage()),
      GoRoute(
        path: Routes.settings,
        builder: (_, __) => const Scaffold(body: Text('halaman pengaturan')),
      ),
      GoRoute(
        path: '/user/:username',
        builder: (_, s) =>
            Scaffold(body: Text('profil ${s.pathParameters['username']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(() => _FakeAuth(user)),
      if (balance != null) walletBalanceProvider.overrideWith((_) => balance),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

void main() {
  testWidgets('shows the username and opens the profile', (tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const AppUser(id: 'u1', email: _email, username: 'tajirsadiq')),
    );
    await tester.pumpAndSettle();

    expect(find.text('tajirsadiq'), findsOneWidget);
    // Never the email, nor any part of it.
    expect(find.textContaining('tajirsadiq.biz'), findsNothing);

    await tester.tap(find.text('Lihat profil'));
    await tester.pumpAndSettle();
    expect(find.text('profil tajirsadiq'), findsOneWidget);
  });

  testWidgets('asks for a username instead of showing the email', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const AppUser(id: 'u1', email: _email)));
    await tester.pumpAndSettle();

    // The email's local part is what this used to render.
    expect(find.text('tajirsadiq.biz'), findsNothing);
    expect(find.text('Belum ada username'), findsOneWidget);

    // `/user/{username}` cannot be built without one, so the row offers the
    // step that unblocks it rather than a dead link.
    expect(find.text('Lihat profil'), findsNothing);
    await tester.tap(find.text('Pilih username'));
    await tester.pumpAndSettle();
    expect(find.text('halaman pengaturan'), findsOneWidget);
  });

  testWidgets('a guest is still called Tamu', (tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(null));
    await tester.pumpAndSettle();

    expect(find.text('Tamu'), findsOneWidget);
    expect(find.text('Belum ada username'), findsNothing);
  });

  // The shimmer never settles, so these pump a frame rather than settle.

  testWidgets('shimmers while the profile is on its way', (tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        const AppUser(id: 'u1', email: _email, profilePending: true),
        balance: Future.value(0),
      ),
    );
    await tester.pump();

    // Not yet known is not the same as not chosen.
    expect(find.text('Belum ada username'), findsNothing);
    expect(find.text('Pilih username'), findsNothing);
    expect(find.byType(ShimmerBox), findsWidgets);
  });

  testWidgets('saldo shimmers while it loads, then shows the figure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final balance = Completer<int>();
    await tester.pumpWidget(
      _host(
        const AppUser(id: 'u1', email: _email, username: 'tajirsadiq'),
        balance: balance.future,
      ),
    );
    await tester.pump();

    expect(find.text('Rp–'), findsNothing);
    expect(find.byType(ShimmerBox), findsOneWidget);

    balance.complete(150000);
    await tester.pump();
    await tester.pump();

    expect(find.byType(ShimmerBox), findsNothing);
    expect(find.text(formatRupiah(150000)), findsOneWidget);
  });
}
