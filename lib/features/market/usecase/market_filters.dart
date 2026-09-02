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

/// The rarities web previews before you expand the group, and the fallback
/// list when facet counts have not arrived (`POPULAR_RARITIES` in
/// `storefront-filter-rail.tsx`).
const marketPopularRarities = ['SAR', 'HR', 'SR', 'AR', 'PROMO'];

/// How many options each expandable facet group shows collapsed —
/// `LOKASI_PREVIEW_COUNT` and the length of `POPULAR_RARITIES` on web.
const marketFacetPreviewCount = 5;

/// `BULK_RARITIES` in `listing-filters.ts` — the commons "exclude bulk"
/// hides. `__none__` stands in for a card with no rarity recorded.
const marketBulkRarities = ['C', 'U', 'R', 'Common', 'Uncommon', 'Rare'];

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
    this.languages = const {},
    this.cities = const {},
    this.verifiedOnly = false,
    this.wishlistOnly = false,
    this.hideBulk = false,
    this.minPrice,
    this.maxPrice,
  });

  final Set<CardCondition> conditions;
  final Set<String> rarities;
  final Set<CardCategory> categories;

  /// Trainer subtypes as the catalog spells them ("Pokémon Tool", accent and
  /// all) — the values the facet counts and `cards.details` carry, rather
  /// than a display label that would match no row.
  final Set<String> trainerSubtypes;

  /// Which language's print to show — `p_card_languages`.
  final Set<CardLanguage> languages;

  /// Seller cities, by name, as they come back in the facet counts.
  final Set<String> cities;
  final bool verifiedOnly;

  /// Only cards on the signed-in buyer's wishlist. Signed out there is no
  /// wishlist to filter by, so the control is hidden entirely.
  final bool wishlistOnly;

  /// Hides commons and uncommons, web's "Exclude bulk (C/U/R)".
  final bool hideBulk;
  final int? minPrice;
  final int? maxPrice;

  int get activeCount =>
      conditions.length +
      rarities.length +
      categories.length +
      trainerSubtypes.length +
      languages.length +
      cities.length +
      (verifiedOnly ? 1 : 0) +
      (wishlistOnly ? 1 : 0) +
      (hideBulk ? 1 : 0) +
      (minPrice != null ? 1 : 0) +
      (maxPrice != null ? 1 : 0);

  /// Ports `excludeRaritiesFor` — what `p_exclude_rarities` should hold while
  /// "exclude bulk" is on, minus any bulk rarity the user has explicitly
  /// asked for, which would otherwise be excluded and selected at once.
  List<String>? get excludeRarities {
    if (!hideBulk) return null;
    final excluded = [
      ...marketBulkRarities,
      '__none__',
    ].where((r) => !rarities.contains(r)).toList();
    return excluded.isEmpty ? null : excluded;
  }

  MarketFilters copyWith({
    Set<CardCondition>? conditions,
    Set<String>? rarities,
    Set<CardCategory>? categories,
    Set<String>? trainerSubtypes,
    Set<CardLanguage>? languages,
    Set<String>? cities,
    bool? verifiedOnly,
    bool? wishlistOnly,
    bool? hideBulk,
    int? Function()? minPrice,
    int? Function()? maxPrice,
  }) {
    return MarketFilters(
      conditions: conditions ?? this.conditions,
      rarities: rarities ?? this.rarities,
      categories: categories ?? this.categories,
      trainerSubtypes: trainerSubtypes ?? this.trainerSubtypes,
      languages: languages ?? this.languages,
      cities: cities ?? this.cities,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      wishlistOnly: wishlistOnly ?? this.wishlistOnly,
      hideBulk: hideBulk ?? this.hideBulk,
      minPrice: minPrice != null ? minPrice() : this.minPrice,
      maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
    );
  }
}
