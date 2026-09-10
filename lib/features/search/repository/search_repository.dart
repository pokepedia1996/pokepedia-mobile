import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/image_url.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/pack_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/utils/card_pricing.dart';
import '../../../shared/models/pokemon_type.dart';
import 'models/advanced_search_query.dart';
import 'dart:convert';

/// Mirrors `MIN_SEARCH_LEN` in `pokepedia-web/lib/utils/constants.ts`.
const minSearchLen = 2;
const _searchBatchSize = 40;

/// How many `cards` rows the open-ended facet scan reads when
/// `get_filter_options` can't supply rarity and regulation mark. Two short
/// columns per row, so this is a few tens of kilobytes — enough to surface
/// every value in normal use without pulling the catalog down.
const _facetScanLimit = 3000;

/// Ports `SearchFilterOptions` (`get_filter_options` RPC, backed by the
/// `filter_options_cache` materialized view) — every facet the "advanced"
/// filter panel can offer. HP/retreat-cost ranges and weakness/resistance
/// types are in the same RPC payload but intentionally left unmodeled here;
/// they're niche enough that a simple/advanced toggle doesn't need them to
/// feel complete.
/// One selectable expansion in the "Ekspansi" facet. The web gets these
/// from `options.expansions` plus a separate symbols map; here the two are
/// read together off the same `expansions` row.
class SearchExpansionOption {
  const SearchExpansionOption({
    required this.code,
    required this.name,
    required this.series,
    this.symbolUrl,
  });

  final String code;
  final String name;
  final String series;
  final String? symbolUrl;
}

class SearchFilterOptions {
  const SearchFilterOptions({
    required this.rarities,
    required this.expansions,
    required this.categories,
    required this.types,
    required this.evolutionStages,
    required this.trainerSubtypes,
    required this.regulationMarks,
    this.error,
  });

  final List<String> rarities;
  final List<SearchExpansionOption> expansions;

  /// Expansion codes in display order, for the `p_expansions` argument.
  List<String> get packMarks => expansions.map((e) => e.code).toList();
  final List<CardCategory> categories;
  final List<PokemonType> types;
  final List<EvolutionStage> evolutionStages;
  final List<TrainerSubtype> trainerSubtypes;
  final List<String> regulationMarks;

  /// Set when one of the two sources failed — the rest of the facets are
  /// still usable, so this is shown as a notice rather than thrown.
  final String? error;
}

/// Ports `optionsOverride ?? deriveFilterOptions(cards)` from
/// `CardFilterBar`: the facet lists never come from one source alone, so a
/// filter is always offered.
///
/// The order is server payload → whatever the current results reveal →
/// the app's own vocabulary. That last step is something the web can't do:
/// category, type, evolution stage and trainer subtype are closed enums
/// here, so the full set is known at compile time and those four facets
/// never depend on the server at all. Rarity and regulation mark are
/// open-ended catalog strings, so they can only come from data.
SearchFilterOptions resolveFilterOptions({
  required SearchFilterOptions? fromServer,
  required List<CardModel> fromResults,
}) {
  final derived = deriveCardFilterOptions(fromResults);

  List<T> pick<T>(List<T>? server, List<T> derived, List<T> vocabulary) {
    if (server != null && server.isNotEmpty) return server;
    if (derived.isNotEmpty) return derived;
    return vocabulary;
  }

  const encoder = JsonEncoder.withIndent('  ');
  final pretty = encoder.convert(fromServer?.categories);
  debugPrint(pretty);

  return SearchFilterOptions(
    categories: pick(
      fromServer?.categories,
      derived.categories,
      CardCategory.values,
    ),
    types: pick(fromServer?.types, derived.types, PokemonType.values),
    evolutionStages: pick(
      fromServer?.evolutionStages,
      derived.evolutionStages,
      EvolutionStage.values,
    ),
    trainerSubtypes: pick(
      fromServer?.trainerSubtypes,
      derived.trainerSubtypes,
      TrainerSubtype.values,
    ),
    // No fixed vocabulary for these two — an empty list means the catalog
    // hasn't told us any yet.
    rarities: pick(fromServer?.rarities, derived.rarities, const []),
    regulationMarks: pick(
      fromServer?.regulationMarks,
      derived.regulationMarks,
      const [],
    ),
    expansions: fromServer?.expansions ?? const [],
    error: fromServer?.error,
  );
}

/// Data access for the Search feature, backed by Supabase. Mirrors
/// `fetchSearchFilterOptions`/`searchCards` in
/// `pokepedia-web/lib/data/client.ts`.
class SearchRepository {
  SearchRepository(this._client);

  final SupabaseClient _client;

  /// [language] scopes the expansion facet: a set exists as one row per
  /// language, so without it the "Ekspansi" filter offers codes that the
  /// catalog currently being searched doesn't contain.
  ///
  /// The two sources are fetched independently on purpose. They fail for
  /// different reasons — `get_filter_options` reads a materialized view
  /// that can be empty, the expansion list is a plain table read — and one
  /// being unavailable shouldn't blank the other's facets. Whatever did
  /// fail is reported through [SearchFilterOptions.error] so the form can
  /// say so instead of silently offering empty dropdowns.
  Future<SearchFilterOptions> fetchFilterOptions({
    String language = 'id',
  }) async {
    final errors = <String>[];

    final results = await Future.wait([
      _fetchOptionPayload(errors),
      _fetchExpansionOptions(language, errors),
    ]);

    final opts = results[0] as Map<String, dynamic>;
    final expansions = results[1] as List<SearchExpansionOption>;

    List<String> stringList(String key) =>
        (opts[key] as List<dynamic>? ?? const [])
            .whereType<String>()
            .where((r) => r.isNotEmpty)
            .toList();

    var rarities = stringList('rarities');
    var regulationMarks = stringList('regulationMarks');

    // Rarity and regulation mark are open-ended catalog strings with no
    // vocabulary to fall back on, so when the cache view can't supply them
    // they're read straight off `cards`. Only in that case — a working cache
    // makes this scan pure waste.
    if (rarities.isEmpty || regulationMarks.isEmpty) {
      final scanned = await _scanOpenEndedFacets(language, errors);
      if (rarities.isEmpty) rarities = scanned.rarities;
      if (regulationMarks.isEmpty) regulationMarks = scanned.regulationMarks;
    }

    // Three facets are parsed from raw catalog strings into enums, and an
    // unrecognized value is dropped — which is indistinguishable from "the
    // catalog has none" once it reaches the UI. Report the difference so an
    // empty dropdown says whether the data was missing or unreadable.
    final rawTypes = stringList('types');
    final rawStages = stringList('evolutionStages');
    final rawSubtypes = stringList('trainerSubtypes');

    final types = rawTypes
        .map(pokemonTypeFromRaw)
        .whereType<PokemonType>()
        .toSet()
        .toList();
    final stages = rawStages
        .map(EvolutionStageX.fromRaw)
        .whereType<EvolutionStage>()
        .toSet()
        .toList();
    final subtypes = rawSubtypes
        .map(TrainerSubtypeX.fromRaw)
        .whereType<TrainerSubtype>()
        .toSet()
        .toList();

    void reportUnparsed(String label, List<String> raw, int parsed) {
      if (raw.isEmpty || parsed > 0) return;
      final sample = raw.take(3).join(', ');
      errors.add('$label: ${raw.length} nilai tidak dikenali ($sample)');
    }

    reportUnparsed('Tipe', rawTypes, types.length);
    reportUnparsed('Evolusi', rawStages, stages.length);
    reportUnparsed('Subtipe', rawSubtypes, subtypes.length);

    return SearchFilterOptions(
      rarities: rarities
        ..sort((a, b) => rarityRank(a).compareTo(rarityRank(b))),
      expansions: expansions,
      categories: stringList(
        'categories',
      ).map(CardCategoryX.fromRaw).toSet().toList(),
      types: types,
      evolutionStages: stages,
      trainerSubtypes: subtypes,
      regulationMarks: regulationMarks..sort(),
      error: errors.isEmpty ? null : errors.join(' · '),
    );
  }

  /// `get_filter_options` returns the whole facet payload as one json
  /// object. It reads `filter_options_cache`, a materialized view created
  /// `WITH NO DATA` and only populated by a trigger on writes to `cards` —
  /// so on a database whose catalog was imported before that trigger
  /// existed, the read raises rather than returning nothing.
  Future<Map<String, dynamic>> _fetchOptionPayload(List<String> errors) async {
    try {
      final data = await _client.rpc('get_filter_options');
      if (data is Map<String, dynamic>) return data;
      errors.add('Daftar filter kosong');
      return const {};
    } on PostgrestException catch (e) {
      errors.add(
        _isUnpopulatedCache(e)
            ? 'Daftar filter belum disiapkan di server '
                  '(filter_options_cache belum di-refresh)'
            : 'Filter: ${e.message}',
      );
      return const {};
    } catch (e) {
      errors.add('Filter: ${_describe(e)}');
      return const {};
    }
  }

  /// Postgres raises `object_not_in_prerequisite_state` (55000) for a read
  /// of a matview that has never been refreshed — worth naming, since it
  /// reads like a client bug otherwise and no client change can fix it.
  static bool _isUnpopulatedCache(PostgrestException e) {
    return e.code == '55000' || e.message.contains('has not been populated');
  }

  Future<List<SearchExpansionOption>> _fetchExpansionOptions(
    String language,
    List<String> errors,
  ) async {
    try {
      final rows = await _client
          .from('expansions')
          .select('code, name_id, set_symbol_url, series:series_id(name_id)')
          .eq('language', language)
          .order('released_at', ascending: false);

      final seen = <String>{};
      final expansions = <SearchExpansionOption>[];
      for (final raw in rows) {
        final code = raw['code'] as String? ?? '';
        if (code.isEmpty || !seen.add(code)) continue;
        final series = PackModel.flattenSeriesEmbed(raw['series']);
        expansions.add(
          SearchExpansionOption(
            code: code,
            name: raw['name_id'] as String? ?? code,
            series: series?['name_id'] as String? ?? 'Lainnya',
            symbolUrl: proxyImageUrl(raw['set_symbol_url'] as String?),
          ),
        );
      }
      return expansions;
    } catch (e) {
      errors.add('Ekspansi: ${_describe(e)}');
      return const [];
    }
  }

  /// Distinct rarity and regulation values over a bounded slice of the
  /// catalog. PostgREST has no DISTINCT, so this reads the two columns and
  /// dedupes here.
  ///
  /// Bounded by [_facetScanLimit]: a value used only by cards outside that
  /// slice won't be offered, which is the trade for not scanning the whole
  /// table on every cold load. `filter_options_cache` is the complete
  /// source — this exists so the two facets aren't empty while it isn't
  /// populated.
  Future<({List<String> rarities, List<String> regulationMarks})>
  _scanOpenEndedFacets(String language, List<String> errors) async {
    try {
      final rows = await _client
          .from('cards')
          .select('rarity, regulation_mark')
          .eq('language', language)
          .limit(_facetScanLimit);

      final rarities = <String>{};
      final regulationMarks = <String>{};
      for (final row in rows) {
        final rarity = (row['rarity'] as String?)?.trim();
        if (rarity != null && rarity.isNotEmpty) rarities.add(rarity);
        final mark = (row['regulation_mark'] as String?)?.trim();
        if (mark != null && mark.isNotEmpty) regulationMarks.add(mark);
      }
      return (
        rarities: rarities.toList(),
        regulationMarks: regulationMarks.toList(),
      );
    } catch (e) {
      errors.add('Kelangkaan/Regulasi: ${_describe(e)}');
      return (rarities: const <String>[], regulationMarks: const <String>[]);
    }
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return error.message;
    }
    return error.toString();
  }

  /// Ports `loadAdvancedSearchPage` — one call to `advanced_search_cards`,
  /// which applies every facet, the ownership filter, the sort and the
  /// paging in SQL.
  ///
  /// The old path used `search_cards_fuzzy` and re-filtered its 40-row page
  /// in Dart, so a facet could only ever narrow the first page of matches
  /// rather than the whole catalog. Empty sets are sent as null because the
  /// RPC treats null as "no filter".
  Future<SearchPage> search({
    required AdvancedSearchQuery query,
    int offset = 0,
    int limit = _searchBatchSize,
  }) async {
    if (!query.hasAnyFilter) return SearchPage.empty;

    final data = await _client.rpc(
      'advanced_search_cards',
      params: {
        'p_language': query.language,
        'p_name': _nullIfBlank(query.name),
        'p_illustrator': _nullIfBlank(query.illustrator),
        'p_categories': _rawList(query.filters.categories, (c) => c.raw),
        'p_types': _rawList(query.filters.types, (t) => t.assetName),
        'p_rarities': _rawList(query.filters.rarities, (r) => r),
        'p_evolution_stages': _rawList(
          query.filters.evolutionStages,
          (s) => s.labelId,
        ),
        'p_trainer_subtypes': _rawList(
          query.filters.trainerSubtypes,
          (s) => s.labelId,
        ),
        'p_regulation_marks': _rawList(query.filters.regulationMarks, (m) => m),
        'p_expansions': _rawList(query.packMarks, (m) => m),
        'p_weakness_types': _rawList(query.weaknessTypes, (t) => t.assetName),
        'p_resistance_types': _rawList(
          query.resistanceTypes,
          (t) => t.assetName,
        ),
        'p_hp_min': query.hpMin,
        'p_hp_max': query.hpMax,
        'p_retreat_min': query.retreatMin,
        'p_retreat_max': query.retreatMax,
        'p_attack_cost_min': query.attackCostMin,
        'p_attack_cost_max': query.attackCostMax,
        'p_ownership': query.ownership.raw,
        'p_sort': query.sort.raw,
        'p_offset': offset,
        'p_limit': limit,
      },
    );

    final rows = (data as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    if (rows.isEmpty) return SearchPage.empty;

    final cards = rows
        .map((row) => row['card'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map(CardModel.fromRow)
        .toList();

    return SearchPage(
      // `advanced_search_cards` returns the catalog row alone — it joins the
      // price cache only to sort by it — so the page is priced here, the way
      // web's client calls `useCardPricesByIds` over the ids it got back.
      // Without it every result reads "Rp-" however well the card is priced.
      cards: await priceCards(_client, cards),
      total: (rows.first['total_count'] as num?)?.toInt() ?? cards.length,
      hasNext: rows.first['has_next'] as bool? ?? false,
    );
  }

  static String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The RPC reads null as "facet not applied", so an empty set must not be
  /// sent as an empty array — that would match nothing.
  static List<String>? _rawList<T>(Set<T> values, String Function(T) raw) {
    if (values.isEmpty) return null;
    return values.map(raw).toList();
  }
}
