import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/seller_products_page.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_listings_notifier.dart';

/// Kelola Listing remembers the tab it was last on, which is right when you
/// come back to it and wrong when something sends you somewhere specific.
/// Tapping "DRAFT" on the dashboard and landing on Aktif reads as the tap
/// having gone somewhere else.
const _me = AppUser(id: 'seller', email: 'seller@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

Future<ProviderContainer> _open(
  WidgetTester tester, {
  SellerListingBucket? initialBucket,
  bool offers = false,
  SellerListingBucket lastUsed = SellerListingBucket.active,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      sellerBucketProvider.overrideWith((ref) => lastUsed),
      sellerListingsProvider.overrideWith((ref) async => <SellerListing>[]),
      sellerDraftsProvider.overrideWith((ref) async => <SellerDraft>[]),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: SellerProductsPage(
          initialBucket: initialBucket,
          initialOffersFilter: offers,
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

void main() {
  group('the link names the tab', () {
    test('every bucket has a route that opens it', () {
      expect(Routes.sellerProductsTab('draft'), '/seller/products?tab=draft');
      expect(
        Routes.sellerProductsWithOffers(),
        '/seller/products?tab=active&offers=1',
      );
    });

    testWidgets('arriving with a tab opens that tab, not the last one', (
      tester,
    ) async {
      final container = await _open(
        tester,
        initialBucket: SellerListingBucket.draft,
        lastUsed: SellerListingBucket.active,
      );

      expect(container.read(sellerBucketProvider), SellerListingBucket.draft);
    });

    testWidgets('arriving without one leaves the tab where it was', (
      tester,
    ) async {
      // Coming back to the page is not the same as being sent to it.
      final container = await _open(
        tester,
        lastUsed: SellerListingBucket.archived,
      );

      expect(
        container.read(sellerBucketProvider),
        SellerListingBucket.archived,
      );
    });

    testWidgets('the offers row arrives with its filter already on', (
      tester,
    ) async {
      final container = await _open(
        tester,
        initialBucket: SellerListingBucket.active,
        offers: true,
      );

      expect(container.read(sellerBucketProvider), SellerListingBucket.active);
      expect(container.read(sellerOfferFilterProvider), isTrue);
    });
  });
}
