import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/market/presentation/widgets/share_store_prompt.dart';
import 'package:pokepedia_mobile/features/market/presentation/widgets/store_poster.dart';
import 'package:pokepedia_mobile/features/market/presentation/widgets/store_share_sheet.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_repository.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_notifier.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';

/// Right after a listing goes up, the store's poster sheet opens on the
/// side just listed — no "share?" step before it.
const _store = StoreModel(
  handle: 'toko-ash',
  storeName: 'Toko Ash',
  tagline: '',
  activeListingCount: 1,
  cityName: 'Jakarta',
  isVerified: true,
  topRated: true,
  itemsSoldCount: 79,
  followersCount: 12,
);

/// Hosts a button that runs the prompt, and counts the listing reads.
Future<({int Function() listingReads})> _open(
  WidgetTester tester, {
  required PosterSide side,
  SellerIdentity identity = const SellerIdentity(storeSlug: 'toko-ash'),
  StoreModel? store = _store,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  var reads = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sellerIdentityProvider.overrideWith((ref) async => identity),
        storeDetailProvider('toko-ash').overrideWith((ref) async => store),
        storeListingsProvider('toko-ash').overrideWith((ref) async {
          reads++;
          return <ListingModel>[];
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => promptShareStorePoster(context, side: side),
              child: const Text('listed'),
            ),
          ),
        ),
      ),
    ),
  );
  return (listingReads: () => reads);
}

Future<void> _listed(WidgetTester tester) async {
  await tester.tap(find.text('listed'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('after a WTS listing: the WTS poster opens straight away', (
    tester,
  ) async {
    await _open(tester, side: PosterSide.wts);
    await _listed(tester);

    expect(find.byType(AlertDialog), findsNothing);
    final sheet = tester.widget<StoreShareSheet>(find.byType(StoreShareSheet));
    expect(sheet.store.handle, 'toko-ash');
    expect(sheet.initialSide, PosterSide.wts);
  });

  testWidgets('after a WTB bid: the WTB poster', (tester) async {
    await _open(tester, side: PosterSide.wtb);
    await _listed(tester);

    expect(
      tester.widget<StoreShareSheet>(find.byType(StoreShareSheet)).initialSide,
      PosterSide.wtb,
    );
  });

  testWidgets('the poster has the listing just put up', (tester) async {
    // The store's listings may be cached from before; they are read again.
    final open = await _open(tester, side: PosterSide.wts);
    final container = ProviderScope.containerOf(
      tester.element(find.text('listed')),
    );
    await container.read(storeListingsProvider('toko-ash').future);
    expect(open.listingReads(), 1);

    await _listed(tester);
    expect(open.listingReads(), 2);
  });

  testWidgets('no storefront, no prompt', (tester) async {
    await _open(tester, side: PosterSide.wtb, identity: const SellerIdentity());
    await _listed(tester);
    expect(find.byType(StoreShareSheet), findsNothing);
  });

  testWidgets('a store that cannot be found, no prompt', (tester) async {
    await _open(tester, side: PosterSide.wts, store: null);
    await _listed(tester);
    expect(find.byType(StoreShareSheet), findsNothing);
  });
}
