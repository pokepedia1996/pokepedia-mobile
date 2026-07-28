import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_model.dart';
import '../../../shared/models/pokemon_type.dart';
import '../../../shared/utils/card_filtering.dart';

/// Mirrors `MIN_SEARCH_LEN` in `pokepedia-web/lib/utils/constants.ts`.
const minSearchLen = 2;
const _searchBatchSize = 40;

/// Ports `SearchFilterOptions` (`get_filter_options` RPC, backed by the
/// `filter_options_cache` materialized view) — every facet the "advanced"
/// filter panel can offer. HP/retreat-cost ranges and weakness/resistance
/// types are in the same RPC payload but intentionally left unmodeled here;
/// they're niche enough that a simple/advanced toggle doesn't need them to
/// feel complete.
class SearchFilterOptions {
  const SearchFilterOptions({
    required this.rarities,
    required this.packMarks,
    required this.categories,
    required this.types,
    required this.evolutionStages,
    required this.trainerSubtypes,
    required this.regulationMarks,
  });

  final List<String> rarities;
  final List<String> packMarks;
  final List<CardCategory> categories;
  final List<PokemonType> types;
  final List<EvolutionStage> evolutionStages;
  final List<TrainerSubtype> trainerSubtypes;
  final List<String> regulationMarks;
}

/// Data access for the Search feature, backed by Supabase. Mirrors
/// `fetchSearchFilterOptions`/`searchCards` in
/// `pokepedia-web/lib/data/client.ts`.
class SearchRepository {
  SearchRepository(this._client);

  final SupabaseClient _client;

  Future<SearchFilterOptions> fetchFilterOptions() async {
    final optionsFuture = _client.rpc('get_filter_options');
    final expansionsFuture = _client
        .from('expansions')
        .select('code')
        .order('released_at', ascending: false);

    final results = await Future.wait<dynamic>([optionsFuture, expansionsFuture]);
    final opts = results[0] as Map<String, dynamic>? ?? const {};
    final expansionRows = results[1] as List<dynamic>;

    List<String> stringList(String key) =>
        (opts[key] as List<dynamic>? ?? const []).whereType<String>().where((r) => r.isNotEmpty).toList();

    final marks =
        expansionRows.map((r) => (r as Map<String, dynamic>)['code'] as String).toSet().toList()..sort();

    return SearchFilterOptions(
      rarities: stringList('rarities')..sort(),
      packMarks: marks,
      categories: stringList('categories').map(CardCategoryX.fromRaw).toSet().toList(),
      types: stringList('types').map(pokemonTypeFromRaw).whereType<PokemonType>().toSet().toList(),
      evolutionStages: stringList(
        'evolutionStages',
      ).map(EvolutionStageX.fromRaw).whereType<EvolutionStage>().toSet().toList(),
      trainerSubtypes: stringList(
        'trainerSubtypes',
      ).map(TrainerSubtypeX.fromRaw).whereType<TrainerSubtype>().toSet().toList(),
      regulationMarks: stringList('regulationMarks')..sort(),
    );
  }

  /// Note: `search_cards_fuzzy` only takes a search query, limit/offset and
  /// `p_rarities` server-side — every other facet (category, type,
  /// evolution stage, trainer subtype, regulation mark, expansion,
  /// illustrator) is applied client-side on top of the RPC's page of
  /// results, same trade-off the old pack-mark-only filtering already made.
  Future<List<CardModel>> search({
    required String query,
    required CardFilters filters,
    required Set<String> packMarks,
    String illustrator = '',
  }) async {
    final q = query.trim();
    if (q.length < minSearchLen) return const [];

    final data = await _client.rpc(
      'search_cards_fuzzy',
      params: {
        'search_query': q,
        'p_limit': _searchBatchSize,
        'p_offset': 0,
        'p_rarities': filters.rarities.isEmpty ? null : filters.rarities.toList(),
      },
    );

    var cards = (data as List<dynamic>)
        .map((row) => (row as Map<String, dynamic>)['card'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map(CardModel.fromRow)
        .toList();

    cards = applyCardFilters(cards, filters);

    if (packMarks.isNotEmpty) {
      cards = cards.where((c) => packMarks.contains(c.expansionCode)).toList();
    }
    final illustratorQuery = illustrator.trim().toLowerCase();
    if (illustratorQuery.isNotEmpty) {
      cards = cards.where((c) => (c.illustrator ?? '').toLowerCase().contains(illustratorQuery)).toList();
    }
    return cards;
  }
}
