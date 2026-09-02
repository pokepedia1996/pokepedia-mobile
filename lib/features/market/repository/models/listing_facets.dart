/// One facet value and how many open listings carry it — web's `FacetItem`
/// (`storefront-data.server.ts`).
class FacetItem {
  const FacetItem({required this.value, required this.count});

  factory FacetItem.fromJson(Map<String, dynamic> json) => FacetItem(
    value: json['value'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? 0,
  );

  final String value;
  final int count;
}

/// What the live marketplace actually holds, from
/// `get_marketplace_listing_facets` — the filter sheet lists the rarities,
/// cities and card types that exist right now with their counts, rather than
/// a hardcoded guess at them.
///
/// Facets depend only on the tab, never on the filters picked inside it,
/// which is why web caches them per side and the app fetches them once.
class ListingFacets {
  const ListingFacets({
    this.rarities = const [],
    this.cities = const [],
    this.categories = const [],
    this.trainerSubtypes = const [],
    this.conditions = const [],
  });

  factory ListingFacets.fromJson(Map<String, dynamic> json) {
    List<FacetItem> items(String key) => ((json[key] as List?) ?? const [])
        .map((e) => FacetItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return ListingFacets(
      rarities: items('rarities'),
      cities: items('cities'),
      categories: items('categories'),
      trainerSubtypes: items('trainerSubtypes'),
      conditions: items('conditions'),
    );
  }

  static const empty = ListingFacets();

  final List<FacetItem> rarities;
  final List<FacetItem> cities;
  final List<FacetItem> categories;
  final List<FacetItem> trainerSubtypes;
  final List<FacetItem> conditions;
}

extension FacetLookup on List<FacetItem> {
  /// The count for [value], or null when the feed holds none of it — the
  /// difference between showing "0" and showing nothing, as on web.
  int? countOf(String value) {
    for (final item in this) {
      if (item.value == value) return item.count;
    }
    return null;
  }

  Map<String, int> get countsByValue => {
    for (final item in this) item.value: item.count,
  };
}
