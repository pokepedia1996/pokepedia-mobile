import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/market/presentation/market_page.dart';
import 'package:pokepedia_mobile/features/market/repository/market_repository.dart';
import 'package:pokepedia_mobile/features/market/repository/models/listing_facets.dart';
import 'package:pokepedia_mobile/features/market/repository/models/market_page.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';

class _FakeRepo implements MarketRepository {
  @override
  Future<MarketListingsPage> fetchListings({
    required MarketBucket bucket,
    String query = '',
    MarketSort sort = MarketSort.createdDesc,
    MarketFilters filters = const MarketFilters(),
    MarketCursor? cursor,
    int limit = 40,
  }) async => const MarketListingsPage.empty();

  @override
  Future<ListingFacets> fetchListingFacets(MarketBucket bucket) async =>
      const ListingFacets(
        categories: [
          FacetItem(value: 'Pokemon', count: 12),
          FacetItem(value: 'Trainer', count: 4),
          FacetItem(value: 'Sealed', count: 2),
        ],
        rarities: [FacetItem(value: 'SAR', count: 3)],
        cities: [
          FacetItem(value: 'Jakarta', count: 5),
          FacetItem(value: 'Bandung', count: 2),
        ],
      );

  @override
  Future<List<StoreModel>> fetchStores({String query = ''}) async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The sheet's order is the order someone works through it: the switch that
/// throws away most of the feed, then what they are hunting, then what it is,
/// then who is selling it.
void main() {
  testWidgets('the sections run bulk, rarity, type, store', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [marketRepositoryProvider.overrideWithValue(_FakeRepo())],
        child: MaterialApp(theme: AppTheme.light, home: const MarketPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    double topOf(String label) => tester.getRect(find.text(label)).top;

    final order = [
      'Feeds',
      'Rarity',
      'Tipe Kartu',
      'Tipe Toko',
      'Bahasa',
      'Kondisi',
      'Lokasi',
      'Harga (IDR)',
    ];
    final tops = [for (final label in order) topOf(label)];

    for (var i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: '${order[i]} should sit below ${order[i - 1]}',
      );
    }

    // Sealed reached the sheet, which only the facet-driven list can do.
    expect(find.text('Produk Segel'), findsOneWidget);
  });
}
