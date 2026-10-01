import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/empty_state.dart';
import 'package:pokepedia_mobile/features/market/presentation/bid_listing_page.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';

/// Both SELECT policies on `listings` require `auth.uid()`, while the
/// marketplace tile that opens this page comes from a SECURITY DEFINER RPC
/// that anon may call. A guest therefore reaches a bid that reads back empty
/// — which is a fact about their session, not about the bid, and must not be
/// reported as "the buyer cancelled".
const _slug = 'bid-slug-1';

class _SignedIn extends AuthNotifier {
  @override
  Future<AppUser?> build() async =>
      const AppUser(id: 'user-1', email: 'ash@pokepedia.id');
}

class _SignedOut extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

Future<void> _pump(WidgetTester tester, {required bool signedIn}) async {
  tester.view.physicalSize = const Size(1170, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/bid/$_slug',
    routes: [
      GoRoute(
        path: '/bid/:slug',
        builder: (_, state) =>
            BidListingPage(slug: state.pathParameters['slug'] ?? ''),
      ),
      GoRoute(path: '/login', builder: (_, __) => const Text('login page')),
      GoRoute(path: '/market', builder: (_, __) => const Text('market page')),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(signedIn ? _SignedIn.new : _SignedOut.new),
        // What RLS hands back either way: nothing.
        bidListingProvider(_slug).overrideWith((ref) async => null),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a guest is asked to sign in, not told the bid is gone', (
    tester,
  ) async {
    await _pump(tester, signedIn: false);

    expect(find.text('Masuk untuk melihat bid ini'), findsOneWidget);
    expect(find.text('Bid tidak lagi tersedia'), findsNothing);
  });

  testWidgets('the prompt sits mid-screen, not under the app bar', (
    tester,
  ) async {
    await _pump(tester, signedIn: false);

    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final dy = tester.getCenter(find.byType(EmptyState)).dy;
    expect(dy, closeTo(screen / 2, 1));
  });

  testWidgets('the sign-in prompt opens the login page', (tester) async {
    await _pump(tester, signedIn: false);

    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('a signed-in reader is still told the bid is gone', (
    tester,
  ) async {
    await _pump(tester, signedIn: true);

    expect(find.text('Bid tidak lagi tersedia'), findsOneWidget);
    expect(find.text('Masuk untuk melihat bid ini'), findsNothing);
  });
}
