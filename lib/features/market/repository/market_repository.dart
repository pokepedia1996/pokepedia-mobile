import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_condition.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/store_model.dart';
import '../usecase/market_filters.dart';
import 'models/listing_facets.dart';
import 'models/store_feedback.dart';

enum MarketBucket { all, listing, buylist, toko }

/// Drops [viewerId]'s own rows out of a marketplace feed.
///
/// A property of the marketplace rather than of one screen: you cannot buy
/// from yourself, so a row you could only look at is noise between the ones
/// you can act on. Signed out, nothing is excluded.
///
/// Applied client-side because `get_recent_marketplace_listings` has no
/// exclusion parameter — its `p_seller_user_id` filters *to* a seller. The
/// cost is that a page can come back slightly short when your own listings
/// fall inside it.
List<ListingModel> excludeOwnListings(
  Iterable<ListingModel> listings,
  String? viewerId,
) {
  if (viewerId == null || viewerId.isEmpty) return listings.toList();
  return listings.where((l) => l.sellerId != viewerId).toList();
}

/// Data access for the Market feature, backed by Supabase. Mirrors
/// `loadMarketplaceListingsPage` (`get_recent_marketplace_listings` RPC)
/// and `loadStoreDirectoryPage` (`search_stores` RPC) on the web. Only GET
/// reads are covered here — buy/offer/checkout flows are a separate pass.
class MarketRepository {
  MarketRepository(this._client);

  final SupabaseClient _client;

  /// `p_window_hours: 0` disables the RPC's default "last 24h only" window
  /// — without it the marketplace would look nearly empty most of the
  /// time. Matches `app/market/page.tsx`'s own explicit override.
  Future<List<ListingModel>> fetchListings({
    required MarketBucket bucket,
    String query = '',
    MarketSort sort = MarketSort.createdDesc,
    MarketFilters filters = const MarketFilters(),
  }) async {
    final side = switch (bucket) {
      MarketBucket.listing => 'ask',
      MarketBucket.buylist => 'bid',
      MarketBucket.all || MarketBucket.toko => null,
    };
    final rows =
        await _client.rpc(
              'get_recent_marketplace_listings',
              params: {
                'p_side': side,
                'p_search': query.trim().isEmpty ? null : query.trim(),
                'p_window_hours': 0,
                'p_limit': 40,
                'p_offset': 0,
                'p_sort': sort.raw,
                if (filters.conditions.isNotEmpty)
                  'p_conditions': filters.conditions.map((c) => c.raw).toList(),
                if (filters.rarities.isNotEmpty)
                  'p_rarities': filters.rarities.toList(),
                if (filters.categories.isNotEmpty)
                  'p_categories': filters.categories.map((c) => c.raw).toList(),
                if (filters.trainerSubtypes.isNotEmpty)
                  'p_trainer_subtypes': filters.trainerSubtypes.toList(),
                if (filters.languages.isNotEmpty)
                  'p_card_languages': filters.languages
                      .map((l) => l.raw)
                      .toList(),
                if (filters.cities.isNotEmpty)
                  'p_cities': filters.cities.toList(),
                if (filters.excludeRarities != null)
                  'p_exclude_rarities': filters.excludeRarities,
                if (filters.verifiedOnly) 'p_verified_only': true,
                if (filters.wishlistOnly) 'p_wishlist_only': true,
                if (filters.minPrice != null) 'p_min_price': filters.minPrice,
                if (filters.maxPrice != null) 'p_max_price': filters.maxPrice,
              },
            )
            as List;
    // Your own listings are dropped here rather than in the pages that show
    // this feed, because it is a property of the marketplace and not of one
    // screen: you cannot buy from yourself, so a row you could only look at
    // is noise between the ones you can act on.
    //
    // Client-side because `get_recent_marketplace_listings` has no exclusion
    // parameter — its `p_seller_user_id` filters *to* a seller. The cost is
    // that a page can come back slightly short when you have listings in it.
    return excludeOwnListings(
      rows.map(
        (r) => ListingModel.fromMarketplaceRow(r as Map<String, dynamic>),
      ),
      _client.auth.currentUser?.id,
    );
  }

  /// The filter sheet's option lists — `get_marketplace_listing_facets`,
  /// the same aggregate web reads server-side. It counts what the open
  /// listings hold, so the sheet can offer every rarity and city that
  /// actually exists rather than a fixed shortlist.
  ///
  /// Counts depend only on the tab, never on the filters chosen inside it,
  /// which is why this takes a bucket and nothing else.
  Future<ListingFacets> fetchListingFacets(MarketBucket bucket) async {
    final side = switch (bucket) {
      MarketBucket.listing => 'ask',
      MarketBucket.buylist => 'bid',
      // Both sides at once: the RPC reads a null side as "don't filter".
      MarketBucket.all || MarketBucket.toko => null,
    };
    final json = await _client.rpc(
      'get_marketplace_listing_facets',
      params: {'p_side': side},
    );
    if (json is! Map) return ListingFacets.empty;
    return ListingFacets.fromJson(json.cast<String, dynamic>());
  }

  Future<List<StoreModel>> fetchStores({String query = ''}) async {
    final rows =
        await _client.rpc(
              'search_stores',
              params: {
                'p_search': query.trim().isEmpty ? null : query.trim(),
                'p_offset': 0,
                'p_limit': 40,
                'p_sort': 'listings_desc',
              },
            )
            as List;
    return rows
        .map((r) => StoreModel.fromDirectoryRow(r as Map<String, dynamic>))
        .toList();
  }

  /// A storefront by its handle, which may be either a store slug or a
  /// username.
  ///
  /// Web has two routes and so knows which it holds — `/market/[slug]` calls
  /// `get_seller_storefront_by_slug`, `/usr/[username]` calls
  /// `get_seller_storefront_by_username`. The app has one route reached from
  /// both kinds of link (the market list and a listing card carry slugs; the
  /// account page, a user profile and the seller dashboard carry usernames),
  /// so it tries the slug and falls back to the username — the same thing
  /// web's `market/[slug]/card/[cardId]` page does.
  Future<StoreModel?> fetchStore(String handle) async {
    var rows =
        await _client.rpc(
              'get_seller_storefront_by_slug',
              params: {'p_slug': handle},
            )
            as List;
    if (rows.isEmpty) {
      rows =
          await _client.rpc(
                'get_seller_storefront_by_username',
                params: {'p_username': handle},
              )
              as List;
    }
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    final sellerId = row['user_id'] as String?;
    // `get_seller_storefront_by_slug` doesn't return a listing count; reuse
    // the listings RPC's own `total_count` instead of a separate query.
    var activeListingCount = 0;
    if (sellerId != null) {
      final listingRows =
          await _client.rpc(
                'get_recent_marketplace_listings',
                params: {
                  'p_seller_user_id': sellerId,
                  'p_window_hours': 0,
                  'p_limit': 1,
                  'p_offset': 0,
                },
              )
              as List;
      if (listingRows.isNotEmpty) {
        activeListingCount =
            ((listingRows.first as Map<String, dynamic>)['total_count'] as num?)
                ?.toInt() ??
            0;
      }
    }
    return StoreModel.fromDetailRow(
      row,
      activeListingCount: activeListingCount,
    );
  }

  Future<List<ListingModel>> fetchStoreListings(String handle) async {
    final store = await fetchStore(handle);
    if (store?.userId == null) return const [];
    return fetchStoreListingsByUserId(store!.userId!);
  }

  Future<List<ListingModel>> fetchStoreListingsByUserId(
    String sellerUserId,
  ) async {
    final rows =
        await _client.rpc(
              'get_recent_marketplace_listings',
              params: {
                'p_seller_user_id': sellerUserId,
                'p_window_hours': 0,
                'p_limit': 100,
                'p_offset': 0,
              },
            )
            as List;
    return rows
        .map((r) => ListingModel.fromMarketplaceRow(r as Map<String, dynamic>))
        .toList();
  }

  /// One seller's open asks (WTS) for a single card, plus how many *other*
  /// sellers also list it — mirrors `get_card_listings` as used by
  /// `app/market/[slug]/card/[cardId]/page.tsx` (`otherSellersCount` there).
  /// Unlike [fetchStoreListingsByUserId] this RPC doesn't join card/store
  /// info onto each row, so [card] and [store] (already resolved by the
  /// caller) are threaded through [ListingModel.fromRow] instead.
  Future<({List<ListingModel> listings, int otherSellersCount})>
  fetchCardListingsForSeller({
    required int cardId,
    required CardModel card,
    required StoreModel store,
  }) async {
    if (store.userId == null)
      return (listings: <ListingModel>[], otherSellersCount: 0);
    final sellerRows =
        await _client.rpc(
              'get_card_listings',
              params: {
                'p_card_id': cardId,
                'p_seller_id': store.userId,
                'p_sort': 'price_asc',
                'p_limit': 50,
                'p_offset': 0,
              },
            )
            as List;
    if (sellerRows.isEmpty)
      return (listings: <ListingModel>[], otherSellersCount: 0);

    final sellerTotal =
        ((sellerRows.first as Map<String, dynamic>)['total_count'] as num?)
            ?.toInt() ??
        0;
    final globalRows =
        await _client.rpc(
              'get_card_listings',
              params: {
                'p_card_id': cardId,
                'p_sort': 'price_asc',
                'p_limit': 1,
                'p_offset': 0,
              },
            )
            as List;
    final globalTotal = globalRows.isEmpty
        ? sellerTotal
        : ((globalRows.first as Map<String, dynamic>)['total_count'] as num?)
                  ?.toInt() ??
              sellerTotal;

    final listings = sellerRows
        .map(
          (r) => ListingModel.fromRow(
            r as Map<String, dynamic>,
            card: card,
            storeSlug: store.handle,
            storeName: store.storeName,
            isVerified: store.isVerified,
            cityName: store.cityName,
            storeLogoUrl: store.logoUrl,
          ),
        )
        .toList();
    return (
      listings: listings,
      otherSellersCount: (globalTotal - sellerTotal).clamp(0, globalTotal),
    );
  }

  /// The seller's feedback summary, bucketed by period server-side.
  Future<StoreFeedbackSummary> fetchFeedbackSummary(String userId) async {
    final result = await _client.rpc(
      'get_feedback_counts_matrix',
      params: {'p_user_id': userId},
    );
    if (result is! Map) {
      return const StoreFeedbackSummary(positive: 0, neutral: 0, negative: 0);
    }
    return StoreFeedbackSummary.fromMatrix(Map<String, dynamic>.from(result));
  }

  /// The reviews themselves, newest first.
  ///
  /// Read straight from `trade_ratings` (`ratings_select_public`) rather
  /// than through `get_feedback_list`: that RPC is in the web repo but isn't
  /// deployed to this project, and PostgREST answers PGRST202 for it.
  Future<List<StoreFeedback>> fetchFeedback(
    String userId, {
    int limit = 20,
  }) async {
    final rows =
        await _client
                .from('trade_ratings')
                .select(
                  'id, rater_id, feedback, comment, reply, created_at, is_auto',
                )
                .eq('rated_id', userId)
                .order('created_at', ascending: false)
                .limit(limit)
            as List;
    if (rows.isEmpty) return const [];

    // Two queries rather than an embed: `trade_ratings.rater_id` references
    // `auth.users`, not `profiles`, so PostgREST has no relationship to
    // traverse (PGRST200).
    final raterIds = rows
        .map((r) => (r as Map<String, dynamic>)['rater_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final profiles =
        await _client
                .from('profiles')
                .select('id, username')
                .inFilter('id', raterIds)
            as List;
    final usernames = {
      for (final row in profiles.cast<Map<String, dynamic>>())
        row['id'] as String: row['username'] as String?,
    };

    return rows.map((r) {
      final row = r as Map<String, dynamic>;
      return StoreFeedback.fromRow(
        row,
        raterUsername: usernames[row['rater_id']],
      );
    }).toList();
  }

  /// `user_reputation`'s precomputed positive-feedback percentage and
  /// (positive − negative) score, mirroring `fetchReputation` in
  /// `lib/user/reputation.ts`. Returns nulls for a seller with no trade
  /// history yet rather than throwing.
  Future<({double? positivePct, int feedbackScore})> fetchReputation(
    String userId,
  ) async {
    final row = await _client
        .from('user_reputation')
        .select('positive_pct, positive_count_total, negative_count_total')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return (positivePct: null, feedbackScore: 0);
    final positiveTotal = (row['positive_count_total'] as num?)?.toInt() ?? 0;
    final negativeTotal = (row['negative_count_total'] as num?)?.toInt() ?? 0;
    return (
      positivePct: (row['positive_pct'] as num?)?.toDouble(),
      feedbackScore: positiveTotal - negativeTotal,
    );
  }
}
