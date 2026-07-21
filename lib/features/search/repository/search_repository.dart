import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_model.dart';

/// Mirrors `MIN_SEARCH_LEN` in `pokepedia-web/lib/utils/constants.ts`.
const minSearchLen = 2;
const _searchBatchSize = 40;

class SearchFilterOptions {
  const SearchFilterOptions({required this.rarities, required this.packMarks});

  final List<String> rarities;
  final List<String> packMarks;
}

/// Data access for the Advanced Search feature, backed by Supabase.
/// Mirrors `fetchSearchFilterOptions`/`searchCards` in
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

    final rarities =
        (opts['rarities'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .where((r) => r.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final marks =
        expansionRows.map((r) => (r as Map<String, dynamic>)['code'] as String).toSet().toList()
          ..sort();

    return SearchFilterOptions(rarities: rarities, packMarks: marks);
  }

  /// Note: `search_cards_fuzzy` has no expansion-code parameter, so pack
  /// filtering is applied client-side on top of the RPC's page of results
  /// — a behavior change from the old client-side-only search is that a
  /// query shorter than [minSearchLen] now returns no results even with
  /// filters selected, matching `searchCards` on web.
  Future<List<CardModel>> search({
    required String query,
    required Set<String> rarities,
    required Set<String> packMarks,
  }) async {
    final q = query.trim();
    if (q.length < minSearchLen) return const [];

    final data = await _client.rpc(
      'search_cards_fuzzy',
      params: {
        'search_query': q,
        'p_limit': _searchBatchSize,
        'p_offset': 0,
        'p_rarities': rarities.isEmpty ? null : rarities.toList(),
      },
    );

    var cards = (data as List<dynamic>)
        .map((row) => (row as Map<String, dynamic>)['card'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map(CardModel.fromRow)
        .toList();

    if (packMarks.isNotEmpty) {
      cards = cards.where((c) => packMarks.contains(c.expansionCode)).toList();
    }
    return cards;
  }
}
