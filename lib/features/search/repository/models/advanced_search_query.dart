import '../../../../shared/models/card_model.dart';
import '../../../../shared/models/pokemon_type.dart';
import '../../../../shared/utils/card_filtering.dart';

/// Ports `ADVANCED_SEARCH_SORT_OPTIONS` from `lib/utils/constants.ts`; the
/// raw values are the ones `advanced_search_cards` accepts for `p_sort`.
enum SearchSort {
  setDesc('set-desc', 'Terbaru'),
  setAsc('set-asc', 'Terlama'),
  nameAsc('name-asc', 'Nama A-Z'),
  nameDesc('name-desc', 'Nama Z-A'),
  numberAsc('number-asc', 'Nomor ↑'),
  numberDesc('number-desc', 'Nomor ↓'),
  rarityAsc('rarity-asc', 'Kelangkaan ↑'),
  rarityDesc('rarity-desc', 'Kelangkaan ↓'),
  priceAsc('price-asc', 'Termurah'),
  priceDesc('price-desc', 'Termahal');

  const SearchSort(this.raw, this.labelId);

  final String raw;
  final String labelId;
}

/// `p_ownership` — needs a signed-in user to mean anything, so the UI only
/// offers it once someone is logged in.
extension OwnershipFilterRaw on OwnershipFilter {
  String get raw {
    switch (this) {
      case OwnershipFilter.all:
        return 'all';
      case OwnershipFilter.owned:
        return 'owned';
      case OwnershipFilter.notOwned:
        return 'not-owned';
    }
  }

  String get labelId {
    switch (this) {
      case OwnershipFilter.all:
        return 'Semua';
      case OwnershipFilter.owned:
        return 'Dimiliki';
      case OwnershipFilter.notOwned:
        return 'Belum dimiliki';
    }
  }
}

/// Every input `advanced_search_cards` takes, ported from the web's
/// `AdvancedSearchFilters` plus its sort and ownership arguments.
///
/// The facets shared with the pack/portfolio browsers stay in [filters] so
/// the same [CardFilters] type keeps driving them; the fields below are the
/// ones only advanced search offers.
class AdvancedSearchQuery {
  const AdvancedSearchQuery({
    this.name = '',
    this.illustrator = '',
    this.filters = const CardFilters(),
    this.packMarks = const {},
    this.weaknessTypes = const {},
    this.resistanceTypes = const {},
    this.hpMin,
    this.hpMax,
    this.retreatMin,
    this.retreatMax,
    this.attackCostMin,
    this.attackCostMax,
    this.sort = SearchSort.nameAsc,
    this.ownership = OwnershipFilter.all,
    this.language = 'id',
  });

  final String name;
  final String illustrator;
  final CardFilters filters;

  /// Expansion codes — `p_expansions`.
  final Set<String> packMarks;
  final Set<PokemonType> weaknessTypes;
  final Set<PokemonType> resistanceTypes;
  final int? hpMin;
  final int? hpMax;
  final int? retreatMin;
  final int? retreatMax;
  final int? attackCostMin;
  final int? attackCostMax;
  final SearchSort sort;
  final OwnershipFilter ownership;
  final String language;

  /// Mirrors the web's `hasFilter` guard: with nothing set, the RPC isn't
  /// called at all and the page shows its "start searching" state. Sort,
  /// ownership and language don't count — they shape a search rather than
  /// being one.
  bool get hasAnyFilter =>
      name.trim().isNotEmpty ||
      illustrator.trim().isNotEmpty ||
      filters.activeCount > 0 ||
      packMarks.isNotEmpty ||
      weaknessTypes.isNotEmpty ||
      resistanceTypes.isNotEmpty ||
      hpMin != null ||
      hpMax != null ||
      retreatMin != null ||
      retreatMax != null ||
      attackCostMin != null ||
      attackCostMax != null;

  /// How many advanced-only facets are set, for the "Filter (3)" badge.
  int get advancedCount =>
      filters.activeCount +
      packMarks.length +
      weaknessTypes.length +
      resistanceTypes.length +
      (illustrator.trim().isEmpty ? 0 : 1) +
      (hpMin != null || hpMax != null ? 1 : 0) +
      (retreatMin != null || retreatMax != null ? 1 : 0) +
      (attackCostMin != null || attackCostMax != null ? 1 : 0);

  AdvancedSearchQuery copyWith({
    String? name,
    String? illustrator,
    CardFilters? filters,
    Set<String>? packMarks,
    Set<PokemonType>? weaknessTypes,
    Set<PokemonType>? resistanceTypes,
    int? Function()? hpMin,
    int? Function()? hpMax,
    int? Function()? retreatMin,
    int? Function()? retreatMax,
    int? Function()? attackCostMin,
    int? Function()? attackCostMax,
    SearchSort? sort,
    OwnershipFilter? ownership,
    String? language,
  }) {
    return AdvancedSearchQuery(
      name: name ?? this.name,
      illustrator: illustrator ?? this.illustrator,
      filters: filters ?? this.filters,
      packMarks: packMarks ?? this.packMarks,
      weaknessTypes: weaknessTypes ?? this.weaknessTypes,
      resistanceTypes: resistanceTypes ?? this.resistanceTypes,
      hpMin: hpMin == null ? this.hpMin : hpMin(),
      hpMax: hpMax == null ? this.hpMax : hpMax(),
      retreatMin: retreatMin == null ? this.retreatMin : retreatMin(),
      retreatMax: retreatMax == null ? this.retreatMax : retreatMax(),
      attackCostMin:
          attackCostMin == null ? this.attackCostMin : attackCostMin(),
      attackCostMax:
          attackCostMax == null ? this.attackCostMax : attackCostMax(),
      sort: sort ?? this.sort,
      ownership: ownership ?? this.ownership,
      language: language ?? this.language,
    );
  }
}

/// One page of `advanced_search_cards`, which reports the total and whether
/// another page exists on every row.
class SearchPage {
  const SearchPage({
    required this.cards,
    required this.total,
    required this.hasNext,
  });

  static const empty = SearchPage(cards: [], total: 0, hasNext: false);

  final List<CardModel> cards;
  final int total;
  final bool hasNext;
}
