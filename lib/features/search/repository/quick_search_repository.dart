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

/// One page of the full results list, plus the spelling web would have
/// corrected the query to.
class FullSearchPage {
  const FullSearchPage({
    required this.cards,
    required this.total,
    required this.hasNext,
    this.correctedQuery,
  });

  static const empty = FullSearchPage(cards: [], total: 0, hasNext: false);

  final List<CardModel> cards;
  final int total;
  final bool hasNext;

  /// Set when nothing matched what was typed and these results are for a
  /// corrected spelling instead — web's "did you mean".
  final String? correctedQuery;

  FullSearchPage withCorrection(String corrected) => FullSearchPage(
    cards: cards,
    total: total,
    hasNext: hasNext,
    correctedQuery: corrected,
  );
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
  /// by relevance.
  ///
  /// When the first page comes back empty it retries once with each word run
  /// through `suggest_search_correction`, which is how web offers "menampilkan
  /// hasil untuk …" on a typo. Later pages skip that: the correction is
  /// already folded into [FullSearchPage.correctedQuery] and passed back in.
  Future<FullSearchPage> searchAll(
    String query, {
    int offset = 0,
    int limit = searchBatchSize,
    CardSortOption? sort,
  }) async {
    final needle = query.trim();
    if (needle.length < minQueryLength) return FullSearchPage.empty;

    final page = await _fuzzyPage(
      needle,
      offset: offset,
      limit: limit,
      sort: sort,
    );
    if (page.cards.isNotEmpty || offset > 0) return page;

    final corrected = await _correct(needle);
    if (corrected == null) return page;

    final retry = await _fuzzyPage(
      corrected,
      offset: offset,
      limit: limit,
      sort: sort,
    );
    if (retry.cards.isEmpty) return page;
    return retry.withCorrection(corrected);
  }

  Future<FullSearchPage> _fuzzyPage(
    String needle, {
    required int offset,
    required int limit,
    required CardSortOption? sort,
  }) async {
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

  /// The query with each word spell-corrected, or null when nothing changed.
  Future<String?> _correct(String needle) async {
    // Web caps the correction at eight words; past that the query is prose,
    // not a card name.
    final words = needle.split(RegExp(r'\s+')).take(8).toList();
    try {
      final corrected = await Future.wait([
        for (final word in words)
          _client
              .rpc('suggest_search_correction', params: {'p_word': word})
              .then((value) => value as String? ?? word)
              .catchError((_) => word),
      ]);
      final joined = corrected.join(' ');
      return joined.toLowerCase() == needle.toLowerCase() ? null : joined;
    } catch (_) {
      return null;
    }
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
