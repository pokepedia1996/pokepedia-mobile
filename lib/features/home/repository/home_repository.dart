import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/pack_model.dart';
import '../../../shared/models/store_model.dart';
import '../../expansions/repository/expansions_repository.dart';
import 'models/store_shelf.dart';

/// Stores per page of "Listing baru dari toko". Each costs a listings read
/// of its own, so a page is kept to what fills a screen or two.
const storeShelfPageSize = 4;

/// Tiles on one store's shelf.
const storeShelfListingCount = 5;

/// Data access for the Home feature, backed by Supabase via
/// [ExpansionsRepository].
class HomeRepository {
  HomeRepository(this._client, this._expansionsRepository);

  final SupabaseClient _client;
  final ExpansionsRepository _expansionsRepository;

  Future<List<PackModel>> fetchExplorePacks({String language = 'id'}) {
    return _expansionsRepository.fetchPacks(language: language);
  }

  /// Resolves the given (most-recent-first) pack slugs against Supabase.
  /// Falls back to the first few explore packs when there's no view
  /// history yet (fresh app session).
  Future<List<PackModel>> fetchRecentlyViewed(
    List<String> slugs, {
    String language = 'id',
  }) async {
    if (slugs.isEmpty) {
      final explore = await fetchExplorePacks(language: language);
      return explore.take(6).toList();
    }

    final rows = await _client
        .from('expansions')
        .select(
          'code, name_id, pack_image_url, set_symbol_url, released_at, '
          'total_cards, sort_order, language, code_lower, '
          'series:series_id(name_id, series_image_url)',
        )
        .inFilter('code_lower', slugs)
        .eq('language', language);

    final bySlug = {
      for (final r in rows) r['code_lower'] as String: PackModel.fromRow(r),
    };
    return slugs.map((s) => bySlug[s]).whereType<PackModel>().toList();
  }

  /// How many of each expansion's cards [collectionId] holds, keyed by the
  /// expansion's slug: distinct cards with a copy or more, so two variants
  /// of one card count as the two cards the checklist lists. Sealed
  /// products are left out, as the expansion page's checklist leaves them.
  Future<Map<String, int>> fetchOwnedCountsByExpansion({
    required String collectionId,
    required List<String> slugs,
    required String language,
  }) async {
    if (slugs.isEmpty) return const {};
    const pageSize = 1000;
    final owned = <String, Set<int>>{};
    for (var from = 0; ; from += pageSize) {
      final rows = await _client
          .from('collection_cards')
          .select('card_id, cards!inner(expansion_code_lower)')
          .eq('collection_id', collectionId)
          .gt('quantity', 0)
          .eq('cards.language', language)
          .inFilter('cards.expansion_code_lower', slugs)
          .neq('cards.category', sealedCategory)
          .range(from, from + pageSize - 1);
      for (final row in rows) {
        final card = row['cards'];
        final slug = card is Map
            ? card['expansion_code_lower'] as String?
            : null;
        if (slug == null) continue;
        owned.putIfAbsent(slug, () => <int>{}).add(row['card_id'] as int);
      }
      if (rows.length < pageSize) break;
    }
    return {for (final e in owned.entries) e.key: e.value.length};
  }

  /// One page of "Listing baru dari toko": the store directory, most
  /// recently listed first (`search_stores`, as the Market tab's Toko list
  /// reads it), each with its newest listings.
  ///
  /// A store whose listings can't be read, or that has none on sale, is left
  /// out rather than drawn as an empty shelf.
  Future<StoreShelfPage> fetchStoreShelves({
    int offset = 0,
    int limit = storeShelfPageSize,
  }) async {
    final rows =
        await _client.rpc(
              'search_stores',
              params: {
                'p_search': null,
                'p_offset': offset,
                'p_limit': limit,
                'p_sort': 'recent_activity',
              },
            )
            as List;
    final stores = rows
        .whereType<Map<String, dynamic>>()
        .map(StoreModel.fromDirectoryRow)
        .toList();
    final shelves = await Future.wait(stores.map(_shelfFor));
    return StoreShelfPage(
      shelves: shelves.whereType<StoreShelf>().toList(),
      nextOffset: offset + rows.length,
      hasMore: rows.length >= limit,
    );
  }

  Future<StoreShelf?> _shelfFor(StoreModel store) async {
    final sellerId = store.userId;
    if (sellerId == null) return null;
    try {
      final rows =
          await _client.rpc(
                'get_recent_marketplace_listings',
                params: {
                  'p_seller_user_id': sellerId,
                  'p_side': 'ask',
                  'p_window_hours': 0,
                  'p_include_custom': true,
                  'p_sort': 'created_desc',
                  'p_limit': storeShelfListingCount,
                  'p_offset': 0,
                },
              )
              as List;
      final listings = rows
          .whereType<Map<String, dynamic>>()
          .map(ListingModel.fromMarketplaceRow)
          .take(storeShelfListingCount)
          .toList();
      return listings.isEmpty
          ? null
          : StoreShelf(store: store, listings: listings);
    } catch (_) {
      return null;
    }
  }
}
