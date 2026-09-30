import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/market/repository/models/listing_facets.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_filters.dart';

/// Web filters the market by four card types; the app offered three, because
/// it drove the list off `CardCategory`, which has no member for sealed
/// products. A booster box could be listed and bought but not filtered for.
void main() {
  test('sealed is one of the types, as on web', () {
    // `CARD_TYPE_ORDER` in storefront-filter-rail.tsx.
    expect(marketCardTypes, ['Pokemon', 'Trainer', 'Energy', 'Sealed']);
    expect(marketCardTypeLabels['Sealed'], 'Produk Segel');
  });

  test('a type filter is sent as the catalog spells it', () {
    const filters = MarketFilters(categories: {'Sealed'});

    // Straight through to `p_categories`, which compares against
    // `cards.category` — so the value has to be the column's, not a label.
    expect(filters.categories, {'Sealed'});
    expect(filters.activeCount, 1);
  });

  test('every type the feed holds counts toward the facets', () {
    const facets = ListingFacets(
      categories: [
        FacetItem(value: 'Sealed', count: 4),
        FacetItem(value: 'Pokemon', count: 120),
      ],
    );

    expect(facets.categories.countOf('Sealed'), 4);
    // Absent is not zero: a type with no listings is left off the sheet
    // rather than offered as a filter that can only empty the grid.
    expect(facets.categories.countOf('Energy'), isNull);
  });
}
