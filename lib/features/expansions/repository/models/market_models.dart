import '../../../../core/utils/image_url.dart';
import '../../../../shared/models/card_condition.dart';

/// One `(condition, day)` row of the `get_market_price_series` RPC — the
/// series behind the market activity chart. [rawPrice] is that day's average
/// transaction price, [avgPrice] the EWMA the web draws as the solid line.
class MarketPricePoint {
  const MarketPricePoint({
    required this.condition,
    required this.day,
    required this.rawPrice,
    this.avgPrice,
  });

  final CardCondition condition;
  final DateTime day;
  final int rawPrice;
  final int? avgPrice;

  /// Mirrors web's `priceOf()` — the EWMA when present, else the raw average.
  int get price => avgPrice ?? rawPrice;

  factory MarketPricePoint.fromRow(Map<String, dynamic> row) {
    return MarketPricePoint(
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      day: DateTime.tryParse(row['day'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      rawPrice: (row['raw_price'] as num?)?.toInt() ?? 0,
      avgPrice: (row['avg_price'] as num?)?.toInt(),
    );
  }
}

/// The headline price shown above the card's market panels, ported from
/// `useMarketHeadline` — the latest point of the NM series over
/// [headlineDays] (falling back to whichever condition has data) plus the
/// move since the start of that window.
class MarketHeadline {
  const MarketHeadline({
    required this.condition,
    required this.price,
    required this.delta,
    required this.deltaPct,
  });

  final CardCondition condition;
  final int price;
  final int delta;
  final double deltaPct;

  /// Builds the headline out of a [MarketPricePoint] series, mirroring
  /// `useMarketHeadline`: prefer NM rows, else every row, oldest → newest.
  /// Returns null when the series is empty.
  static MarketHeadline? fromSeries(List<MarketPricePoint> series) {
    var rows = series.where((p) => p.condition == CardCondition.nm).toList();
    if (rows.isEmpty) rows = [...series];
    if (rows.isEmpty) return null;
    rows.sort((a, b) => a.day.compareTo(b.day));

    final latest = rows.last.price;
    final earliest = rows.first.price;
    final delta = latest - earliest;
    return MarketHeadline(
      condition: rows.last.condition,
      price: latest,
      delta: delta,
      deltaPct: earliest > 0 ? (delta / earliest) * 100 : 0,
    );
  }
}

/// The window `useMarketHeadline` measures its delta over.
const headlineDays = 7;

/// Where a cached market price came from, mirroring
/// `card_market_price_cache.source`.
enum CardPriceSource { confirmed, ask, bid }

/// One row of the `get_card_prices_by_ids` RPC — the cached headline price
/// used as a fallback when a card has no sale history to build a series from.
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

/// A price level of the order book — every open listing on one side at one
/// price/condition, aggregated by the `get_order_book` RPC.
class OrderBookLevel {
  const OrderBookLevel({
    required this.isBid,
    required this.price,
    required this.orderCount,
    required this.totalQuantity,
    required this.condition,
    this.viewerOwns = false,
  });

  final bool isBid;
  final int price;
  final int orderCount;
  final int totalQuantity;
  final CardCondition condition;

  /// True when one of the listings at this level belongs to the signed-in
  /// user — drives the "Kamu" chip on the row.
  final bool viewerOwns;

  factory OrderBookLevel.fromRow(Map<String, dynamic> row) {
    final orderCount = (row['order_count'] as num?)?.toInt() ?? 0;
    return OrderBookLevel(
      isBid: (row['side'] as String?) == 'bid',
      price: (row['price'] as num?)?.toInt() ?? 0,
      orderCount: orderCount,
      totalQuantity: (row['total_quantity'] as num?)?.toInt() ?? orderCount,
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      viewerOwns: row['viewer_owns'] as bool? ?? false,
    );
  }
}

/// Ports `OrderBookData` from `features/card-detail/server/order-book.ts`.
class OrderBookData {
  const OrderBookData({
    required this.bids,
    required this.asks,
    required this.activeMatchCount,
  });

  static const empty = OrderBookData(bids: [], asks: [], activeMatchCount: 0);

  /// Highest bids first / lowest asks first, as the RPC already orders them.
  final List<OrderBookLevel> bids;
  final List<OrderBookLevel> asks;

  /// In-flight transactions for this card, shown next to the header.
  final int activeMatchCount;

  int? get bestBid => bids.isEmpty ? null : bids.first.price;
  int? get bestAsk => asks.isEmpty ? null : asks.first.price;

  int? get spread {
    final bid = bestBid;
    final ask = bestAsk;
    return (bid == null || ask == null) ? null : ask - bid;
  }

  bool get isEmpty => bids.isEmpty && asks.isEmpty;
}

/// Where a recorded sale came from — an on-platform order or an imported
/// external (Facebook group) sale.
enum SaleSource { internal, external }

/// One row of the `get_card_sales` RPC — a settled transaction shown in the
/// "Histori Transaksi" table.
class CardSale {
  const CardSale({
    required this.id,
    required this.source,
    required this.price,
    required this.date,
    this.condition,
    this.facebookUrl,
    this.photoUrls = const [],
  });

  final String id;
  final SaleSource source;
  final int price;
  final DateTime date;
  final CardCondition? condition;

  /// Set for imported sales — the row's date links out to the post.
  final String? facebookUrl;

  /// Photos of the sold copy, opened in the lightbox from the date cell.
  final List<String> photoUrls;

  factory CardSale.fromRow(Map<String, dynamic> row) {
    final conditionRaw = row['condition'] as String?;
    final photos = row['photo_urls'];
    return CardSale(
      id: row['sale_id'] as String? ?? '',
      source: (row['source'] as String?) == 'external'
          ? SaleSource.external
          : SaleSource.internal,
      price: (row['price'] as num?)?.toInt() ?? 0,
      date: DateTime.tryParse(row['stamped_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      condition:
          conditionRaw == null ? null : CardConditionX.fromRaw(conditionRaw),
      facebookUrl: row['facebook_url'] as String?,
      photoUrls: photos is List
          ? photos
                .map((u) => proxyImageUrl(u as String?))
                .whereType<String>()
                .toList()
          : const [],
    );
  }
}

/// A page of [CardSale]s plus the total the RPC reports, so the section can
/// show "{total} transaksi" without a second count query.
class CardSalesPage {
  const CardSalesPage({required this.sales, required this.total});

  static const empty = CardSalesPage(sales: [], total: 0);

  final List<CardSale> sales;
  final int total;
}
