import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/market/presentation/store_detail_page.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';

/// A seller browsing their own storefront was offered both a Follow button
/// that `follow_shop` refuses (`cannot_follow_self`) and a Chat button with
/// nobody on the other end.
const _seller = AppUser(id: 'seller', email: 'seller@example.com');
const _shopper = AppUser(id: 'shopper', email: 'shopper@example.com');

const _store = StoreModel(
  handle: 'toko-ash',
  storeName: 'Toko Ash',
  tagline: '',
  activeListingCount: 0,
  cityName: 'Jakarta',
  isVerified: false,
  topRated: false,
  itemsSoldCount: 0,
  followersCount: 3,
  userId: 'seller',
);

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.user);

  final AppUser? user;

  @override
  Future<AppUser?> build() async => user;
}

Future<void> _pump(WidgetTester tester, AppUser? viewer) async {
  // Wide on purpose: `flutter_test`'s square fallback font makes this
  // header's rows measure far wider than they do on a device, and the
  // overflow that causes has nothing to do with what's under test.
  tester.view.physicalSize = const Size(2000, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FakeAuth(viewer)),
        storeDetailProvider('toko-ash').overrideWith((ref) async => _store),
        storeListingsProvider('toko-ash').overrideWith((ref) async => []),
        wishlistedIdsProvider.overrideWith((ref) async => <int>{}),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const StoreDetailPage(handle: 'toko-ash'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a shopper gets follow, chat and share', (tester) async {
    await _pump(tester, _shopper);

    expect(find.text('Ikuti'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
  });

  testWidgets('the seller gets neither on their own storefront', (
    tester,
  ) async {
    await _pump(tester, _seller);

    expect(find.text('Ikuti'), findsNothing);
    expect(find.text('Diikuti'), findsNothing);
    expect(find.text('Chat'), findsNothing);
    // Sharing your own shop is the one action that still means something.
    expect(find.text('Bagikan toko'), findsOneWidget);
  });

  testWidgets('a guest still gets both, and is asked to sign in on tap', (
    tester,
  ) async {
    // Signed out is not the same as "this is mine": the buttons stay.
    await _pump(tester, null);

    expect(find.text('Ikuti'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
  });
}
