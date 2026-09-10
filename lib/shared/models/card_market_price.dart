import 'card_condition.dart';

/// Where a cached market price came from, mirroring
/// `card_market_price_cache.source`.
enum CardPriceSource { confirmed, ask, bid }

/// One row of the `get_card_prices_by_ids` / `get_pack_card_prices` RPCs —
/// the cached headline price, what it was a week earlier, and which side of
/// the book it came from.
///
/// Shared rather than owned by the expansions feature: the catalog tiles,
/// the scanner and the card detail page all read the same cache.
class CardMarketPrice {
  const CardMarketPrice({
    required this.price,
    required this.condition,
    required this.source,
    this.price7dAgo,
  });

  final int price;
  final CardCondition condition;
  final CardPriceSource source;
  final int? price7dAgo;

  factory CardMarketPrice.fromRow(Map<String, dynamic> row) {
    return CardMarketPrice(
      price: (row['price'] as num?)?.toInt() ?? 0,
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      source: switch (row['source'] as String?) {
        'ask' => CardPriceSource.ask,
        'bid' => CardPriceSource.bid,
        _ => CardPriceSource.confirmed,
      },
      price7dAgo: (row['price_7d_ago'] as num?)?.toInt(),
    );
  }
}
