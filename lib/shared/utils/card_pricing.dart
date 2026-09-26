import 'package:flutter/foundation.dart';
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

  final slices = <List<int>>[
    for (var start = 0; start < ids.length; start += _priceChunk)
      ids.sublist(
        start,
        start + _priceChunk > ids.length ? ids.length : start + _priceChunk,
      ),
  ];

  // Chunks go out together rather than one after another: a two-thousand-card
  // collection paid five round trips end to end before a single tile could
  // show a price, and the page waits on all of it. A few at a time, though —
  // a big enough collection is a lot of chunks, and firing all of them at once
  // just moves the queue from the client to the database.
  for (var i = 0; i < slices.length; i += _maxInFlight) {
    final wave = slices.skip(i).take(_maxInFlight);
    for (final chunk in await Future.wait(
      wave.map((s) => _fetchChunk(client, s)),
    )) {
      prices.addAll(chunk);
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

/// How many price chunks are in flight at once.
const _maxInFlight = 4;

/// One chunk, parsed. Everything that can throw is inside the guard —
/// reaching the RPC, and reading the rows it answers with. A price the
/// client can't parse costs that card its price and nothing else: the grid
/// coped with a null price long before this, and the collection behind it
/// must not fail to load over one bad row.
Future<Map<int, CardMarketPrice>> _fetchChunk(
  SupabaseClient client,
  List<int> ids,
) async {
  final prices = <int, CardMarketPrice>{};
  try {
    final rows = await client.rpc(
      'get_card_prices_by_ids',
      params: {'p_card_ids': ids},
    );
    if (rows is! List) return prices;
    for (final row in rows) {
      if (row is! Map) continue;
      try {
        final parsed = Map<String, dynamic>.from(row);
        final id = (parsed['card_id'] as num?)?.toInt();
        if (id != null && parsed['price'] != null) {
          prices[id] = CardMarketPrice.fromRow(parsed);
        }
      } catch (error) {
        if (kDebugMode) debugPrint('[pricing] bad row skipped: $error');
      }
    }
  } catch (error) {
    if (kDebugMode) debugPrint('[pricing] chunk failed: $error');
  }
  return prices;
}
