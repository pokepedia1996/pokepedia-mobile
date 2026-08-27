import '../models/card_model.dart';
import '../models/pokemon_type.dart';
import '../../features/expansions/repository/expansions_repository.dart'
    show compareNatural;

/// Ports `CardFilters`/`applyFilters`/`deriveFilterOptions` from
/// `components/card/card-filters.tsx`.
class CardFilters {
  const CardFilters({
    this.search = '',
    this.categories = const {},
    this.types = const {},
    this.rarities = const {},
    this.evolutionStages = const {},
    this.trainerSubtypes = const {},
    this.regulationMarks = const {},
  });

  final String search;
  final Set<CardCategory> categories;
  final Set<PokemonType> types;
  final Set<String> rarities;
  final Set<EvolutionStage> evolutionStages;
  final Set<TrainerSubtype> trainerSubtypes;
  final Set<String> regulationMarks;

  int get activeCount =>
      categories.length +
      types.length +
      rarities.length +
      evolutionStages.length +
      trainerSubtypes.length +
      regulationMarks.length;

  CardFilters copyWith({
    String? search,
    Set<CardCategory>? categories,
    Set<PokemonType>? types,
    Set<String>? rarities,
    Set<EvolutionStage>? evolutionStages,
    Set<TrainerSubtype>? trainerSubtypes,
    Set<String>? regulationMarks,
  }) => CardFilters(
    search: search ?? this.search,
    categories: categories ?? this.categories,
    types: types ?? this.types,
    rarities: rarities ?? this.rarities,
    evolutionStages: evolutionStages ?? this.evolutionStages,
    trainerSubtypes: trainerSubtypes ?? this.trainerSubtypes,
    regulationMarks: regulationMarks ?? this.regulationMarks,
  );

  /// Clears every facet but keeps the free-text search, matching the web's
  /// "Hapus filter" behavior.
  CardFilters clearedKeepingSearch() => CardFilters(search: search);
}

List<CardModel> applyCardFilters(List<CardModel> cards, CardFilters filters) {
  var result = cards;
  if (filters.search.trim().isNotEmpty) {
    final q = filters.search.trim().toLowerCase();
    result = result.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.collectorNumber.toLowerCase().contains(q) ||
          (c.illustrator?.toLowerCase().contains(q) ?? false);
    }).toList();
  }
  if (filters.categories.isNotEmpty) {
    result = result
        .where((c) => filters.categories.contains(c.category))
        .toList();
  }
  if (filters.types.isNotEmpty) {
    result = result.where((c) {
      final cardTypes = c.category == CardCategory.energy
          ? [if (c.details.energyType != null) c.details.energyType!]
          : c.details.pokemonTypes;
      return cardTypes.any(filters.types.contains);
    }).toList();
  }
  if (filters.rarities.isNotEmpty) {
    result = result.where((c) => filters.rarities.contains(c.rarity)).toList();
  }
  if (filters.evolutionStages.isNotEmpty) {
    result = result
        .where(
          (c) =>
              c.details.evolutionStage != null &&
              filters.evolutionStages.contains(c.details.evolutionStage),
        )
        .toList();
  }
  if (filters.trainerSubtypes.isNotEmpty) {
    result = result
        .where(
          (c) =>
              c.details.trainerSubtype != null &&
              filters.trainerSubtypes.contains(c.details.trainerSubtype),
        )
        .toList();
  }
  if (filters.regulationMarks.isNotEmpty) {
    result = result
        .where(
          (c) =>
              c.regulationMark != null &&
              filters.regulationMarks.contains(c.regulationMark),
        )
        .toList();
  }
  return result;
}

class CardFilterOptions {
  const CardFilterOptions({
    required this.categories,
    required this.types,
    required this.rarities,
    required this.evolutionStages,
    required this.trainerSubtypes,
    required this.regulationMarks,
  });

  final List<CardCategory> categories;
  final List<PokemonType> types;
  final List<String> rarities;
  final List<EvolutionStage> evolutionStages;
  final List<TrainerSubtype> trainerSubtypes;
  final List<String> regulationMarks;
}

CardFilterOptions deriveCardFilterOptions(List<CardModel> cards) {
  final categories = <CardCategory>{};
  final types = <PokemonType>{};
  final rarities = <String>{};
  final evolutionStages = <EvolutionStage>{};
  final trainerSubtypes = <TrainerSubtype>{};
  final regulationMarks = <String>{};

  for (final c in cards) {
    categories.add(c.category);
    if (c.category == CardCategory.energy) {
      if (c.details.energyType != null) types.add(c.details.energyType!);
    } else {
      types.addAll(c.details.pokemonTypes);
    }
    rarities.add(c.rarity ?? 'Tanpa tanda');
    if (c.details.evolutionStage != null)
      evolutionStages.add(c.details.evolutionStage!);
    if (c.details.trainerSubtype != null)
      trainerSubtypes.add(c.details.trainerSubtype!);
    if (c.regulationMark != null && c.regulationMark!.isNotEmpty) {
      regulationMarks.add(c.regulationMark!);
    }
  }

  final sortedRarities = rarities.toList()
    ..sort((a, b) => rarityRank(a).compareTo(rarityRank(b)));

  return CardFilterOptions(
    categories: categories.toList()..sort((a, b) => a.name.compareTo(b.name)),
    types: types.toList()..sort((a, b) => a.name.compareTo(b.name)),
    rarities: sortedRarities,
    evolutionStages: evolutionStages.toList()
      ..sort((a, b) => a.index.compareTo(b.index)),
    trainerSubtypes: trainerSubtypes.toList()
      ..sort((a, b) => a.index.compareTo(b.index)),
    regulationMarks: regulationMarks.toList()..sort(),
  );
}

/// Ports `RARITY_ORDER`/`getRarityRank` from `lib/utils/index.tsx`.
const _rarityOrder = <String, int>{
  'Tanpa tanda': 0,
  'C': 1,
  'U': 2,
  'R': 3,
  'RR': 4,
  'RRR': 5,
  'PROMO': 6,
  'AR': 7,
  'CHR': 7,
  'TR': 7,
  'K': 7,
  'A': 7,
  'PR': 7,
  'S': 7,
  'Shining': 8,
  'ACE': 9,
  'SR': 10,
  'MA': 10,
  'CSR': 11,
  'SSR': 12,
  'SAR': 13,
  'UR': 14,
  'HR': 15,
  'MUR': 16,
  'BWR': 16,
};

int rarityRank(String rarity) => _rarityOrder[rarity] ?? 0x7fffffff;

/// Ports `CARD_SORT_OPTIONS`/`PACK_DETAIL_SORT_OPTIONS` + `sortCards` from
/// `lib/utils/constants.ts` / `lib/utils/sorting.ts`.
enum CardSortOption {
  numberAsc,
  numberDesc,
  nameAsc,
  nameDesc,
  rarityAsc,
  rarityDesc,
  priceAsc,
  priceDesc,
}

extension CardSortOptionX on CardSortOption {
  String get label => switch (this) {
    CardSortOption.numberAsc => 'Nomor ↑',
    CardSortOption.numberDesc => 'Nomor ↓',
    CardSortOption.nameAsc => 'Nama A-Z',
    CardSortOption.nameDesc => 'Nama Z-A',
    CardSortOption.rarityAsc => 'Kelangkaan ↑',
    CardSortOption.rarityDesc => 'Kelangkaan ↓',
    CardSortOption.priceAsc => 'Termurah',
    CardSortOption.priceDesc => 'Termahal',
  };
}

List<CardModel> sortCards(List<CardModel> cards, CardSortOption sortBy) {
  final result = [...cards];
  result.sort((a, b) {
    switch (sortBy) {
      case CardSortOption.nameAsc:
        return a.name.compareTo(b.name);
      case CardSortOption.nameDesc:
        return b.name.compareTo(a.name);
      case CardSortOption.numberAsc:
        return compareNatural(a.collectorNumber, b.collectorNumber);
      case CardSortOption.numberDesc:
        return compareNatural(b.collectorNumber, a.collectorNumber);
      case CardSortOption.rarityAsc:
        return rarityRank(
          a.rarity ?? 'Tanpa tanda',
        ).compareTo(rarityRank(b.rarity ?? 'Tanpa tanda'));
      case CardSortOption.rarityDesc:
        return rarityRank(
          b.rarity ?? 'Tanpa tanda',
        ).compareTo(rarityRank(a.rarity ?? 'Tanpa tanda'));
      case CardSortOption.priceAsc:
        return _comparePrice(a, b, 1);
      case CardSortOption.priceDesc:
        return _comparePrice(a, b, -1);
    }
  });
  return result;
}

int _comparePrice(CardModel a, CardModel b, int dir) {
  final pa = a.marketPrice;
  final pb = b.marketPrice;
  if (pa == null && pb == null) return 0;
  if (pa == null) return 1;
  if (pb == null) return -1;
  return dir * (pa - pb);
}

enum CardViewMode { grid, list }

enum OwnershipFilter { all, owned, notOwned }
