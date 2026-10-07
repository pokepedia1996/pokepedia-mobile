import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/utils/card_pricing.dart';
import '../../../shared/models/store_model.dart';

/// What the search bar offers while you type — the cards and stores behind
/// web's `SearchSuggestionsDropdown`.
class QuickSearchResults {
  const QuickSearchResults({this.cards = const [], this.stores = const []});

  static const empty = QuickSearchResults();

  final List<CardModel> cards;
  final List<StoreModel> stores;

  bool get isEmpty => cards.isEmpty && stores.isEmpty;
}

/// One page of the full results list.
class FullSearchPage {
  const FullSearchPage({
    required this.cards,
    required this.total,
    required this.hasNext,
  });

  static const empty = FullSearchPage(cards: [], total: 0, hasNext: false);

  final List<CardModel> cards;
  final int total;
  final bool hasNext;
}

/// The two lookups behind the search bar's suggestions.
///
/// Both are the same RPCs the website's navbar calls — `search_cards_picker`
/// for the catalog and `search_stores` for shops — so a query typed here
/// ranks the same way it does there.
class QuickSearchRepository {
  QuickSearchRepository(this._client);

  final SupabaseClient _client;

  /// Web's `MIN_SEARCH_LEN`: one letter matches most of the catalog, which is
  /// a slow query and a useless list.
  static const minQueryLength = 2;

  /// `SearchSuggestionsDropdown` renders at most this many of each.
  static const cardLimit = 5;
  static const storeLimit = 4;

  /// `SEARCH_BATCH_SIZE` — one page of the full results list.
  static const searchBatchSize = 40;

  Future<QuickSearchResults> search(String query) async {
    final needle = query.trim();
    if (needle.length < minQueryLength) return QuickSearchResults.empty;

    // In parallel: neither depends on the other, and the dropdown shows both
    // at once.
    final results = await Future.wait([
      _searchCards(needle),
      _searchStores(needle),
    ]);
    return QuickSearchResults(
      cards: results[0] as List<CardModel>,
      stores: results[1] as List<StoreModel>,
    );
  }

  Future<List<CardModel>> _searchCards(String needle) async {
    try {
      final rows =
          await _client.rpc(
                'search_cards_picker',
                params: {
                  'search_query': needle,
                  'p_limit': cardLimit,
                  'p_languages': null,
                  'p_regulation_marks': null,
                },
              )
              as List;
      return rows
          .map((r) => (r as Map<String, dynamic>)['card'])
          .whereType<Map<String, dynamic>>()
          .map(CardModel.fromRow)
          .toList();
    } catch (_) {
      // A suggestion list is a convenience: half of it is better than an
      // error where the results should be.
      return const [];
    }
  }

  /// One page of full results — `search_cards_fuzzy`, the RPC behind web's
  /// `/search?q=`, which matches names, numbers, expansion codes,
  /// illustrators, rarities, attacks and abilities in one pass and ranks them
  /// by relevance. Typos are absorbed by its trigram fallback.
  Future<FullSearchPage> searchAll(
    String query, {
    int offset = 0,
    int limit = searchBatchSize,
    CardSortOption? sort,
  }) async {
    final needle = query.trim();
    if (needle.length < minQueryLength) return FullSearchPage.empty;

    final rows =
        await _client.rpc(
              'search_cards_fuzzy',
              params: {
                'search_query': needle,
                'p_limit': limit,
                'p_offset': offset,
                // Null sorts by relevance, which is what an unsorted search
                // should lead with.
                'p_sort': sort?.raw,
                // Facets are applied on the client, over the rows already
                // fetched — the same way the expansion detail page filters
                // its list.
                'p_categories': null,
                'p_types': null,
                'p_rarities': null,
                'p_evolution_stages': null,
                'p_trainer_subtypes': null,
                'p_regulation_marks': null,
                'p_languages': null,
              },
            )
            as List;

    final maps = rows.whereType<Map<String, dynamic>>().toList();
    if (maps.isEmpty) return FullSearchPage.empty;

    final cards = maps
        .map((row) => row['card'])
        .whereType<Map<String, dynamic>>()
        .map(CardModel.fromRow)
        .toList();
    return FullSearchPage(
      // Priced here for the same reason the advanced search page is:
      // `search_cards_fuzzy` returns catalog rows, which carry no price.
      cards: await priceCards(_client, cards),
      total: (maps.first['total_count'] as num?)?.toInt() ?? cards.length,
      hasNext: maps.first['has_next'] as bool? ?? false,
    );
  }

  Future<List<StoreModel>> _searchStores(String needle) async {
    try {
      final rows =
          await _client.rpc(
                'search_stores',
                params: {
                  'p_search': needle,
                  'p_offset': 0,
                  'p_limit': storeLimit,
                  'p_sort': 'listings_desc',
                },
              )
              as List;
      return rows
          .map((r) => StoreModel.fromDirectoryRow(r as Map<String, dynamic>))
          .where((store) => store.handle.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
