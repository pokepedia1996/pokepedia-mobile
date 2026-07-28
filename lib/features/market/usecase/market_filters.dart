import '../../../shared/models/card_condition.dart';
import '../../../shared/models/card_model.dart';

/// Ports `SORT_OPTIONS` from `storefront-filter-rail.tsx`.
enum MarketSort { createdDesc, priceAsc, priceDesc, createdAsc }

extension MarketSortX on MarketSort {
  /// The `get_recent_marketplace_listings` RPC's `p_sort` value.
  String get raw {
    switch (this) {
      case MarketSort.createdDesc:
        return 'created_desc';
      case MarketSort.priceAsc:
        return 'price_asc';
      case MarketSort.priceDesc:
        return 'price_desc';
      case MarketSort.createdAsc:
        return 'created_asc';
    }
  }

  String get labelId {
    switch (this) {
      case MarketSort.createdDesc:
        return 'Terbaru';
      case MarketSort.priceAsc:
        return 'Termurah';
      case MarketSort.priceDesc:
        return 'Termahal';
      case MarketSort.createdAsc:
        return 'Terlama';
    }
  }
}

/// The rarity checkboxes web falls back to when it has no facet-count data
/// (`POPULAR_RARITIES` in `storefront-filter-rail.tsx`).
const marketPopularRarities = ['SAR', 'HR', 'SR', 'AR', 'PROMO'];

/// Marketplace-listing filter facets — a subset of
/// `StorefrontFilterRailProps`, mapped straight onto
/// `get_recent_marketplace_listings` RPC params so filtering happens
/// server-side rather than over the already-paginated page of results.
class MarketFilters {
  const MarketFilters({
    this.conditions = const {},
    this.rarities = const {},
    this.categories = const {},
    this.trainerSubtypes = const {},
    this.verifiedOnly = false,
    this.minPrice,
    this.maxPrice,
  });

  final Set<CardCondition> conditions;
  final Set<String> rarities;
  final Set<CardCategory> categories;
  final Set<TrainerSubtype> trainerSubtypes;
  final bool verifiedOnly;
  final int? minPrice;
  final int? maxPrice;

  int get activeCount =>
      conditions.length +
      rarities.length +
      categories.length +
      trainerSubtypes.length +
      (verifiedOnly ? 1 : 0) +
      (minPrice != null ? 1 : 0) +
      (maxPrice != null ? 1 : 0);

  MarketFilters copyWith({
    Set<CardCondition>? conditions,
    Set<String>? rarities,
    Set<CardCategory>? categories,
    Set<TrainerSubtype>? trainerSubtypes,
    bool? verifiedOnly,
    int? Function()? minPrice,
    int? Function()? maxPrice,
  }) {
    return MarketFilters(
      conditions: conditions ?? this.conditions,
      rarities: rarities ?? this.rarities,
      categories: categories ?? this.categories,
      trainerSubtypes: trainerSubtypes ?? this.trainerSubtypes,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      minPrice: minPrice != null ? minPrice() : this.minPrice,
      maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
    );
  }
}
