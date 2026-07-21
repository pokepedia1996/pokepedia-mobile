import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/pack_model.dart';

/// Mirrors `EXPANSION_COLUMNS` in `pokepedia-web/lib/data/client.ts`.
const _expansionColumns =
    'code, name_id, pack_image_url, set_symbol_url, released_at, total_cards, sort_order, language, series:series_id(name_id, series_image_url)';

/// The `cards` fields `CardModel.fromRow` actually reads — narrower than
/// web's `CARD_LIST_COLUMNS` since our model doesn't need the embedded
/// `expansions`/`series` join (that's only used web-side for series-based
/// sort enrichment we don't replicate here).
const _cardColumns =
    'id, name_id, expansion_code, collector_number, rarity, category, image_url, illustrator, regulation_mark, language, variant, details';

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
    return bySeries.entries.map((e) => SeriesGroup(series: e.key, packs: e.value)).toList();
  }

  Future<PackModel?> fetchPack(String slug) async {
    final row = await _client
        .from('expansions')
        .select(_expansionColumns)
        .eq('code_lower', slug.toLowerCase())
        .maybeSingle();
    return row == null ? null : PackModel.fromRow(row);
  }

  Future<List<CardModel>> fetchCardsForPack(String slug, {String language = 'id'}) async {
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
    final row = await _client.from('cards').select(_cardColumns).eq('id', id).maybeSingle();
    return row == null ? null : CardModel.fromRow(row);
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
          'accepts_offers, view_count, created_at, user_id, card:cards($_cardColumns)',
        )
        .eq('card_id', cardId)
        .eq('status', 'open')
        .order('created_at', ascending: false);

    if (rows.isEmpty) return const [];

    final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
    final storeRows = await _client
        .from('seller_profiles')
        .select('user_id, store_slug, store_name, is_verified, city_name')
        .inFilter('user_id', userIds);
    final storesByUser = {for (final s in storeRows) s['user_id'] as String: s};

    return rows.map((row) {
      final card = CardModel.fromRow(row['card'] as Map<String, dynamic>);
      final store = storesByUser[row['user_id'] as String];
      return ListingModel.fromRow(
        row,
        card: card,
        storeSlug: store?['store_slug'] as String? ?? '',
        storeName: store?['store_name'] as String? ?? 'Toko',
        isVerified: store?['is_verified'] as bool? ?? false,
        cityName: store?['city_name'] as String? ?? '',
      );
    }).toList();
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
  return RegExp(
    r'(\d+)|(\D+)',
  ).allMatches(s).map<Object>((m) {
    final numStr = m.group(1);
    if (numStr != null) return int.parse(numStr);
    return (m.group(2) ?? '').toLowerCase();
  }).toList();
}
