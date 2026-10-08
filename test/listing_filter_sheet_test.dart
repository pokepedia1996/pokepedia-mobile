import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/market/presentation/widgets/listing_filter_sheet.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';

/// A storefront's filter used to offer condition and sort alone, where web's
/// storefront rail filters by type (with Trainer's subtypes), language,
/// rarity, condition, city and price. It is now the market's own sheet,
/// pointed at the store's counts and without the market-only switches.
final _facets = FutureProvider<ListingFacets>(
  (ref) async => ListingFacets.fromJson({
    'categories': [
      {'value': 'Pokemon', 'count': 1532},
      {'value': 'Trainer', 'count': 373},
      {'value': 'Energy', 'count': 27},
    ],
    'trainerSubtypes': [
      {'value': 'Item', 'count': 135},
      {'value': 'Supporter', 'count': 146},
    ],
    'rarities': [
      {'value': 'SAR', 'count': 4},
    ],
    'conditions': [
      {'value': 'NM', 'count': 1800},
    ],
    'cities': [
      {'value': 'Kota Surabaya', 'count': 1900},
    ],
  }),
);

Future<void> _open(
  WidgetTester tester, {
  required void Function(MarketFilters, MarketSort) onApply,
  bool storeMode = true,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListingFilterSheet(
            initial: const MarketFilters(),
            facets: _facets,
            onApply: onApply,
            showWishlist: !storeMode,
            showHideBulk: !storeMode,
            showVerified: !storeMode,
            sortOptions: storeMode
                ? const [
                    MarketSort.createdDesc,
                    MarketSort.priceAsc,
                    MarketSort.priceDesc,
                  ]
                : const [],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a store gets web\'s storefront sections, with its counts', (
    tester,
  ) async {
    await _open(tester, onApply: (_, __) {});

    for (final section in [
      'Urutkan',
      'Tipe Kartu',
      'Bahasa',
      'Rarity',
      'Kondisi',
      'Harga (IDR)',
    ]) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
    expect(find.text('1532'), findsOneWidget);
    expect(find.text('Supporter'), findsOneWidget);

    // Market-only: they narrow nothing within one seller's shop.
    expect(find.text('Feeds'), findsNothing);
    expect(find.text('Tipe Toko'), findsNothing);
    // One city only, so Lokasi has nothing to choose between.
    expect(find.text('Lokasi'), findsNothing);
  });

  testWidgets('applying hands back the draft and the sort', (tester) async {
    MarketFilters? applied;
    MarketSort? sorted;
    await _open(
      tester,
      onApply: (filters, sort) {
        applied = filters;
        sorted = sort;
      },
    );

    await tester.tap(find.text('Supporter'));
    await tester.tap(find.text('Termurah'));
    await tester.pump();
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    // A subtype brings its category with it, as on web.
    expect(applied?.trainerSubtypes, {'Supporter'});
    expect(applied?.categories, contains('Trainer'));
    expect(sorted, MarketSort.priceAsc);
  });

  testWidgets('the market keeps its own switches', (tester) async {
    await _open(tester, onApply: (_, __) {}, storeMode: false);
    expect(find.text('Feeds'), findsOneWidget);
    expect(find.text('Tipe Toko'), findsOneWidget);
    expect(find.text('Urutkan'), findsNothing);
  });
}
