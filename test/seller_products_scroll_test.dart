import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/seller_products_page.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_listings_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The page is one scroll, not a fixed head over a scrolling list. The
/// chrome above the cards is five rows deep — header, search, tabs, heading,
/// two buttons — and pinning it left a phone showing barely two listings
/// through a slot.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

SellerDraft _draft(int id) => SellerDraft(
  id: id,
  card: CardModel(
    id: id,
    category: CardCategory.pokemon,
    nameId: 'Kartu $id',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '$id/165',
    rarity: 'AR',
  ),
  condition: CardCondition.nm,
  quantity: 1,
  photoCount: 0,
  price: 45000,
);

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        sellerBucketProvider.overrideWith((ref) => SellerListingBucket.draft),
        sellerDraftsProvider.overrideWith(
          (ref) async => [for (var i = 1; i <= 12; i++) _draft(i)],
        ),
        sellerListingsProvider.overrideWith((ref) async => <SellerListing>[]),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const SellerProductsPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('the header scrolls away with the cards', (tester) async {
    await _open(tester);

    // The heading is part of the scroll, not pinned above it.
    expect(find.text('Kelola Listing'), findsOneWidget);
    final before = tester.getTopLeft(find.text('Kelola Listing')).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await tester.pump();

    final after = tester.getTopLeft(find.text('Kelola Listing')).dy;
    expect(
      after,
      lessThan(before),
      reason: 'the heading should move up with the page',
    );
  });

  testWidgets('one scroll view owns the page, not one per section', (
    tester,
  ) async {
    await _open(tester);

    // The horizontal chip strips are scrollables too, so this counts only
    // the vertical one: there must be exactly one.
    final vertical = tester
        .widgetList<Scrollable>(find.byType(Scrollable))
        .where((s) => s.axisDirection == AxisDirection.down);
    expect(vertical, hasLength(1));
  });

  testWidgets('the selection bar stays put while the page scrolls', (
    tester,
  ) async {
    await _open(tester);

    await tester.tap(find.text('Kartu 1'));
    await tester.pump();
    expect(find.text('1 dipilih'), findsOneWidget);
    final before = tester.getTopLeft(find.text('1 dipilih')).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await tester.pump();

    // It is about what is already chosen, not what is on screen.
    expect(tester.getTopLeft(find.text('1 dipilih')).dy, before);
  });
}
