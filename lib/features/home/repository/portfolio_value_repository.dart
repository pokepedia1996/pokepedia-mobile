import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/portfolio_value.dart';

/// Builds the collection-worth history behind the Beranda chart.
///
/// There is no stored series for "what this portfolio was worth" — nothing
/// snapshots it — so the series is derived the only way the schema allows:
/// take the cards the user holds, read each one's daily close out of
/// `price_history`, carry the last known price forward across days that card
/// didn't trade, and sum the holdings per day.
///
/// `price_history` is world-readable (`price_history_select_public` is
/// `USING (true)`, granted to `authenticated`), so this runs entirely on the
/// user's own session.
///
/// Note that this table is empty on production today, which means the chart
/// has nothing to draw until the pipeline that fills it
/// (`append_price_history_closed_days`) starts producing rows. The derivation
/// is written against the real schema so it lights up on its own once they
/// appear, rather than being stubbed against invented numbers.
class PortfolioValueRepository {
  PortfolioValueRepository(this._client);

  final SupabaseClient _client;

  /// PostgREST puts the id list in the query string, so long collections go
  /// out in batches.
  static const _idChunk = 200;

  /// A ceiling on rows pulled per batch. A wide collection over MAX could
  /// otherwise ask for far more than a phone should hold; the series is
  /// drawn from what fits and the caller can narrow the range.
  static const _rowLimit = 10000;

  /// Daily portfolio value for [holdings] over [range].
  ///
  /// Returns an empty list when no price history covers these cards — the
  /// chart shows its own empty state rather than a flat line at zero, which
  /// would read as "your collection is worthless".
  Future<List<PortfolioValuePoint>> fetchValueSeries({
    required List<PortfolioHolding> holdings,
    required PortfolioRange range,
  }) async {
    if (holdings.isEmpty) return const [];

    final quantityByCard = <int, int>{};
    for (final holding in holdings) {
      quantityByCard[holding.cardId] =
          (quantityByCard[holding.cardId] ?? 0) + holding.quantity;
    }

    final ids = quantityByCard.keys.toList();
    final from = range.days == null
        ? null
        : DateTime.now().toUtc().subtract(Duration(days: range.days!));

    // card_id -> (day -> close price)
    final priceByCard = <int, Map<DateTime, int>>{};

    for (var i = 0; i < ids.length; i += _idChunk) {
      final end = i + _idChunk;
      final batch = ids.sublist(i, end > ids.length ? ids.length : end);

      var query = _client
          .from('price_history')
          .select('card_id, trade_date, close_price')
          .inFilter('card_id', batch);
      if (from != null) {
        query = query.gte('trade_date', _isoDay(from));
      }
      final rows = await query
          .order('trade_date', ascending: true)
          .limit(_rowLimit);

      for (final row in rows) {
        final cardId = row['card_id'] as int?;
        final day = DateTime.tryParse(row['trade_date'] as String? ?? '');
        final close = (row['close_price'] as num?)?.round();
        if (cardId == null || day == null || close == null) continue;
        // Several conditions and variants can report the same day; the last
        // one wins, matching how the headline price collapses to one number
        // per card.
        (priceByCard[cardId] ??= {})[_dateOnly(day)] = close;
      }
    }

    if (priceByCard.isEmpty) return const [];

    final days = <DateTime>{
      for (final byDay in priceByCard.values) ...byDay.keys,
    }.toList()..sort();

    // Forward-fill: a card keeps its last traded price on days it didn't
    // trade, which is what makes the sum a portfolio value rather than a
    // count of that day's trades.
    final lastKnown = <int, int>{};
    final series = <PortfolioValuePoint>[];
    for (final day in days) {
      var total = 0;
      for (final entry in quantityByCard.entries) {
        final price = priceByCard[entry.key]?[day];
        if (price != null) lastKnown[entry.key] = price;
        final carried = lastKnown[entry.key];
        if (carried != null) total += carried * entry.value;
      }
      series.add(PortfolioValuePoint(day: day, value: total));
    }
    return series;
  }

  static DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static String _isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

final portfolioValueRepositoryProvider = Provider(
  (ref) => PortfolioValueRepository(Supabase.instance.client),
);
