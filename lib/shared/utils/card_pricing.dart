import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/card_market_price.dart';
import '../models/card_model.dart';

/// Postgres takes a large array happily, but a URL-encoded RPC body doesn't:
/// a several-thousand-card collection is chunked rather than sent whole.
const _priceChunk = 400;

/// Prices a batch of cards through `get_card_prices_by_ids`.
///
/// `cards` rows carry no price — the catalog table has none. The card detail
/// page fetched one price at a time through this same RPC, which is why a
/// card showed a value there while the collection, the portfolio total and
/// Beranda's headline all read zero. This is the batch call the RPC was
/// built for: it already returns `card_id` per row.
///
/// Returns the input list with the cached price stamped on where one
/// exists, and untouched where none does. The whole row is carried, not
/// just the number: the tiles draw the week's move from `price_7d_ago` and
/// `source`.
Future<List<CardModel>> priceCards(
  SupabaseClient client,
  List<CardModel> cards,
) async {
  if (cards.isEmpty) return cards;

  final ids = {for (final card in cards) card.id}.toList();
  final prices = <int, CardMarketPrice>{};

  for (var start = 0; start < ids.length; start += _priceChunk) {
    final end = start + _priceChunk;
    final slice = ids.sublist(start, end > ids.length ? ids.length : end);
    try {
      final rows = await client.rpc(
        'get_card_prices_by_ids',
        params: {'p_card_ids': slice},
      );
      if (rows is! List) continue;
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final id = (row['card_id'] as num?)?.toInt();
        if (id != null && row['price'] != null) {
          prices[id] = CardMarketPrice.fromRow(row);
        }
      }
    } catch (_) {
      // A pricing failure leaves the cards unpriced rather than taking the
      // collection down with it — the grid already copes with a null price.
    }
  }

  if (prices.isEmpty) return cards;
  return [
    for (final card in cards)
      if (prices[card.id] case final price?)
        card.copyWith(price: price)
      else
        card,
  ];
}
