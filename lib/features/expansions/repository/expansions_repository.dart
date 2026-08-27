import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_condition.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/pack_model.dart';
import 'models/market_models.dart';

/// Mirrors `EXPANSION_COLUMNS` in `pokepedia-web/lib/data/client.ts`.
const _expansionColumns =
    'code, name_id, pack_image_url, set_symbol_url, released_at, total_cards, sort_order, language, series:series_id(name_id, series_image_url)';

/// The `cards` fields `CardModel.fromRow` actually reads — narrower than
/// web's `CARD_LIST_COLUMNS` since our model doesn't need the embedded
/// `expansions`/`series` join (that's only used web-side for series-based
/// sort enrichment we don't replicate here).
const _cardColumns =
    'id, name_id, expansion_code, collector_number, rarity, category, image_url, illustrator, regulation_mark, language, variant, details';

/// `bulk_upsert_user_cards` and `bulk_remove_user_cards` both raise past
/// 500 ids in one call, matching the web's `BULK_CARD_LIMIT`.
const _bulkChunkSize = 500;

/// Data access for the Expansions feature, backed by Supabase. Mirrors
/// `fetchPacks`/`fetchPacksGroupedBySeries`/`fetchCardsByPack` in
/// `pokepedia-web/lib/data/client.ts`.
class ExpansionsRepository {
  ExpansionsRepository(this._client);

  final SupabaseClient _client;

  Future<List<PackModel>> fetchPacks({String language = 'id'}) async {
    final rows = await _client
        .from('expansions')
        .select(_expansionColumns)
        .eq('language', language)
        .order('released_at', ascending: false)
        .order('sort_order', ascending: false);
    return rows.map((r) => PackModel.fromRow(r)).toList();
  }

  Future<List<SeriesGroup>> fetchSeriesGroups({String language = 'id'}) async {
    final packs = await fetchPacks(language: language);
    final bySeries = <String, List<PackModel>>{};
    for (final pack in packs) {
      bySeries.putIfAbsent(pack.series, () => []).add(pack);
    }
    return bySeries.entries
        .map(
          (e) => SeriesGroup(
            series: e.key,
            packs: e.value,
            seriesImageUrl: e.value.first.seriesImageUrl,
          ),
        )
        .toList();
  }

  /// An expansion code is only unique *per language* — the same set exists
  /// as separate `id`/`en`/`jp` rows — so the slug has to be paired with a
  /// language, exactly as every catalog query in `lib/data/client.ts` does.
  /// Without it `maybeSingle()` throws once a code exists in more than one
  /// language.
  Future<PackModel?> fetchPack(String slug, {String language = 'id'}) async {
    final row = await _client
        .from('expansions')
        .select(_expansionColumns)
        .eq('language', language)
        .eq('code_lower', slug.toLowerCase())
        .maybeSingle();
    return row == null ? null : PackModel.fromRow(row);
  }

  Future<List<CardModel>> fetchCardsForPack(
    String slug, {
    String language = 'id',
  }) async {
    final rows = await _client
        .from('cards')
        .select(_cardColumns)
        .eq('language', language)
        .eq('expansion_code_lower', slug.toLowerCase())
        .order('collector_number', ascending: true);
    final cards = rows.map((r) => CardModel.fromRow(r)).toList();
    cards.sort((a, b) => compareNatural(a.collectorNumber, b.collectorNumber));
    return cards;
  }

  Future<CardModel?> fetchCard(int id) async {
    final row = await _client
        .from('cards')
        .select(_cardColumns)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : CardModel.fromRow(row);
  }

  /// Ports `fetchCardsByNameServer` — the other prints of the same card
  /// name, newest expansion first. This is what feeds the web's "Kartu
  /// Terkait" rail, and it's why the rail is empty for a card that only
  /// ever had one print.
  Future<List<CardModel>> fetchCardsByName(
    String name, {
    required int excludeId,
    String language = 'id',
    int limit = 20,
  }) async {
    if (name.isEmpty) return const [];
    final rows = await _client
        .from('cards')
        .select(_cardColumns)
        .eq('name_id', name)
        .eq('language', language)
        .neq('id', excludeId)
        .order('expansion_code', ascending: false)
        .limit(limit);
    return rows.map((r) => CardModel.fromRow(r)).toList();
  }

  /// Ports `fetchEvolutionChainCardsServer` — calls the same
  /// `get_evolution_pool` RPC the web uses to walk `details.evolves_from`
  /// in both directions from [seedNames].
  ///
  /// The rows come back exactly as the RPC returns them, as on the web. Do
  /// not filter them by the card's language: the RPC ends in
  /// `SELECT DISTINCT ON (name_id) ... ORDER BY name_id, id`, so each
  /// species is already collapsed to a single row — whichever language holds
  /// the lowest card id, which is usually the English print. Filtering to
  /// one language therefore deletes species out of the middle of a chain,
  /// and `buildEvolutionStages` then finds a single stage and renders
  /// nothing at all. `DISTINCT ON` is also why no filter is needed to keep
  /// duplicate prints of one species out of a stage: there can only ever be
  /// one row per name.
  ///
  /// The catch is cosmetic and shared with the web: a chain viewed on an
  /// Indonesian card can show another language's artwork for the stages
  /// whose surviving row is English, and a translated name ('Elektroda')
  /// sits alongside the English one ('Electrode') as a separate entry in the
  /// same stage. Fixing that needs a `p_language` argument on the RPC so the
  /// filter runs *before* the `DISTINCT ON`.
  Future<List<CardModel>> fetchEvolutionPool(List<String> seedNames) async {
    if (seedNames.isEmpty) return const [];
    final rows = await _client.rpc(
      'get_evolution_pool',
      params: {'seed_names': seedNames},
    );
    return (rows as List)
        .map((r) => CardModel.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// Sums `user_cards.quantity` for a card across any variant rows.
  /// Mirrors `fetchUserCardQuantities` in `lib/products/portfolio.ts`.
  Future<int> fetchOwnedQuantity(String userId, int cardId) async {
    final rows = await _client
        .from('user_cards')
        .select('quantity')
        .eq('user_id', userId)
        .eq('card_id', cardId);
    return rows.fold<int>(0, (sum, r) => sum + (r['quantity'] as int? ?? 0));
  }

  /// Ports `upsertUserCard` (`lib/products/portfolio.ts`) — `delta` is added
  /// to the user's existing quantity for this card via the same atomic
  /// server-side RPC the web uses.
  Future<String?> upsertUserCard({
    required String userId,
    required int cardId,
    required int delta,
  }) async {
    try {
      await _client.rpc(
        'upsert_user_card_atomic',
        params: {'p_user_id': userId, 'p_card_id': cardId, 'p_delta': delta},
      );
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Ports `fetchUserCardQuantities` (`lib/products/portfolio.ts`) — the
  /// owned quantity for a whole page of cards, summed across variant rows.
  ///
  /// PostgREST puts `in.(...)` in the query string, so a large expansion
  /// would build a URL long enough for some proxies to reject; the ids go
  /// out in [_bulkChunkSize] batches for that reason.
  Future<Map<int, int>> fetchOwnedQuantities(
    String userId,
    List<int> cardIds,
  ) async {
    final ids = _sanitizeCardIds(cardIds);
    if (ids.isEmpty) return const {};

    final quantities = <int, int>{};
    for (final batch in _batches(ids)) {
      final rows = await _client
          .from('user_cards')
          .select('card_id, quantity')
          .eq('user_id', userId)
          .inFilter('card_id', batch)
          .gt('quantity', 0);
      for (final row in rows) {
        final id = row['card_id'] as int;
        quantities[id] = (quantities[id] ?? 0) + (row['quantity'] as int? ?? 0);
      }
    }
    return quantities;
  }

  /// Ports `bulkAddUserCards` — `p_delta` is applied to every listed card in
  /// one atomic RPC call.
  Future<({int count, String? error})> bulkUpsertUserCards({
    required String userId,
    required List<int> cardIds,
    required int delta,
  }) {
    return _runBulk(
      cardIds,
      (batch) => _client.rpc(
        'bulk_upsert_user_cards',
        params: {'p_user_id': userId, 'p_card_ids': batch, 'p_delta': delta},
      ),
    );
  }

  /// Ports `bulkRemoveUserCards`. Note the RPC does more than clear
  /// `user_cards`: it also deletes the user's `user_inventory` rows for
  /// these cards and logs an `out` activity row for each, so callers have
  /// to revalidate inventory too.
  Future<({int count, String? error})> bulkRemoveUserCards({
    required String userId,
    required List<int> cardIds,
  }) {
    return _runBulk(
      cardIds,
      (batch) => _client.rpc(
        'bulk_remove_user_cards',
        params: {'p_user_id': userId, 'p_card_ids': batch},
      ),
    );
  }

  /// Both bulk RPCs raise past 500 ids, which is why the web guards with
  /// `BULK_CARD_LIMIT` and refuses the call outright. Batching instead means
  /// an expansion larger than the limit still works.
  Future<({int count, String? error})> _runBulk(
    List<int> cardIds,
    Future<dynamic> Function(List<int> batch) call,
  ) async {
    final ids = _sanitizeCardIds(cardIds);
    if (ids.isEmpty) return (count: 0, error: null);

    var count = 0;
    for (final batch in _batches(ids)) {
      try {
        final result = await call(batch);
        if (result is int) count += result;
      } on PostgrestException catch (e) {
        // Earlier batches already committed, so the partial count travels
        // with the error and the caller still revalidates.
        return (count: count, error: e.message);
      }
    }
    return (count: count, error: null);
  }

  /// Ports `sanitizeCardIds` — dedupes and drops non-positive ids.
  static List<int> _sanitizeCardIds(List<int> cardIds) =>
      cardIds.where((id) => id > 0).toSet().toList();

  static Iterable<List<int>> _batches(List<int> ids) sync* {
    for (var i = 0; i < ids.length; i += _bulkChunkSize) {
      final end = i + _bulkChunkSize;
      yield ids.sublist(i, end > ids.length ? ids.length : end);
    }
  }

  /// Open listings for a card, joined with the seller's store info.
  /// `listings.user_id` and `seller_profiles.user_id` both reference
  /// `auth.users` rather than one another, so PostgREST can't embed them
  /// in a single query — this fetches listings+cards, then batches a
  /// second `seller_profiles` lookup and merges in Dart.
  Future<List<ListingModel>> fetchListingsForCard(int cardId) async {
    final rows = await _client
        .from('listings')
        .select(
          'id, slug, side, price, condition, quantity, qty_locked, status, '
          'accepts_offers, view_count, created_at, user_id, photo_urls, '
          'card:cards($_cardColumns)',
        )
        .eq('card_id', cardId)
        .eq('status', 'open')
        .order('created_at', ascending: false);

    if (rows.isEmpty) return const [];

    final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
    final storeRows = await _client
        .from('seller_profiles')
        .select(
          'user_id, store_slug, store_name, store_logo_url, is_verified, city_name',
        )
        .inFilter('user_id', userIds);
    final storesByUser = {for (final s in storeRows) s['user_id'] as String: s};

    // Reputation drives the seller's star on each row. It's a separate table
    // that a buyer may not be able to read under RLS, so a failure here just
    // leaves the score at 0 rather than dropping the whole listings list.
    var reputationByUser = <String, Map<String, dynamic>>{};
    try {
      final reputationRows = await _client
          .from('user_reputation')
          .select('user_id, positive_count_total, negative_count_total')
          .inFilter('user_id', userIds);
      reputationByUser = {
        for (final r in reputationRows) r['user_id'] as String: r,
      };
    } catch (_) {
      // Swallowed — rows fall back to a 0 reputation score.
    }

    return rows.map((row) {
      final card = CardModel.fromRow(row['card'] as Map<String, dynamic>);
      final userId = row['user_id'] as String;
      final store = storesByUser[userId];
      final reputation = reputationByUser[userId];
      return ListingModel.fromRow(
        row,
        card: card,
        storeSlug: store?['store_slug'] as String? ?? '',
        storeName: store?['store_name'] as String? ?? 'Toko',
        isVerified: store?['is_verified'] as bool? ?? false,
        cityName: store?['city_name'] as String? ?? '',
        storeLogoUrl: store?['store_logo_url'] as String?,
        sellerFeedbackScore:
            ((reputation?['positive_count_total'] as num?)?.toInt() ?? 0) -
            ((reputation?['negative_count_total'] as num?)?.toInt() ?? 0),
      );
    }).toList();
  }

  /// Ports `useMarketHeadline` / `MarketActivity`'s chart fetch — the daily
  /// price series (raw average + EWMA) per condition for the last [days]
  /// days, or the last year when [days] is null.
  Future<List<MarketPricePoint>> fetchMarketPriceSeries(
    int cardId, {
    String? variantKey,
    int? days,
  }) async {
    final rows = await _client.rpc(
      'get_market_price_series',
      params: {
        'p_card_id': cardId,
        'p_variant_key': variantKey,
        'p_days': days,
      },
    );
    return (rows as List)
        .map((r) => MarketPricePoint.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  /// The cached headline price for a card (`useCardPricesByIds` web-side),
  /// used when a card has no sale history for a series.
  Future<CardMarketPrice?> fetchCardMarketPrice(int cardId) async {
    final rows = await _client.rpc(
      'get_card_prices_by_ids',
      params: {
        'p_card_ids': [cardId],
      },
    );
    final list = rows as List;
    if (list.isEmpty) return null;
    return CardMarketPrice.fromRow(list.first as Map<String, dynamic>);
  }

  /// Ports `fetchOrderBook` (`features/card-detail/server/order-book.ts`) —
  /// the aggregated bid/ask ladder plus the count of in-flight matches.
  /// `p_viewer_id` is what flags the viewer's own bids server-side.
  Future<OrderBookData> fetchOrderBook(
    int cardId, {
    String? variantKey,
    CardCondition? condition,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    final results = await Future.wait([
      _client.rpc(
        'get_order_book',
        params: {
          'p_card_id': cardId,
          'p_variant_key': variantKey,
          'p_condition': condition?.raw,
          'p_viewer_id': viewerId,
        },
      ),
      _client.rpc(
        'get_active_match_count',
        params: {'p_card_id': cardId, 'p_variant_key': variantKey},
      ),
    ]);

    final bids = <OrderBookLevel>[];
    final asks = <OrderBookLevel>[];
    for (final raw in results[0] as List) {
      final level = OrderBookLevel.fromRow(raw as Map<String, dynamic>);
      (level.isBid ? bids : asks).add(level);
    }

    return OrderBookData(
      bids: bids,
      asks: asks,
      activeMatchCount: (results[1] as num?)?.toInt() ?? 0,
    );
  }

  /// Settled transactions for a card — the "Histori Transaksi" table. Mirrors
  /// `GET /api/cards/[id]/sales`, which wraps this same RPC.
  Future<CardSalesPage> fetchCardSales(
    int cardId, {
    String? variantKey,
    int offset = 0,
    int limit = 20,
  }) async {
    final rows = await _client.rpc(
      'get_card_sales',
      params: {
        'p_card_id': cardId,
        'p_variant_key': variantKey,
        'p_offset': offset,
        'p_limit': limit,
      },
    );
    final list = rows as List;
    if (list.isEmpty) return CardSalesPage.empty;
    return CardSalesPage(
      sales: list
          .map((r) => CardSale.fromRow(r as Map<String, dynamic>))
          .toList(),
      total:
          ((list.first as Map<String, dynamic>)['total_count'] as num?)
              ?.toInt() ??
          list.length,
    );
  }
}

/// Ports `compareNatural`/`naturalSortKey` from `client.ts` so collector
/// numbers sort "9" before "10" instead of lexically.
int compareNatural(String a, String b) {
  final partsA = _naturalParts(a);
  final partsB = _naturalParts(b);
  for (var i = 0; i < partsA.length && i < partsB.length; i++) {
    final pa = partsA[i];
    final pb = partsB[i];
    if (pa is int && pb is int) {
      if (pa != pb) return pa.compareTo(pb);
    } else if (pa is int) {
      return -1;
    } else if (pb is int) {
      return 1;
    } else if (pa != pb) {
      return (pa as String).compareTo(pb as String);
    }
  }
  return partsA.length - partsB.length;
}

List<Object> _naturalParts(String s) {
  return RegExp(r'(\d+)|(\D+)').allMatches(s).map<Object>((m) {
    final numStr = m.group(1);
    if (numStr != null) return int.parse(numStr);
    return (m.group(2) ?? '').toLowerCase();
  }).toList();
}
