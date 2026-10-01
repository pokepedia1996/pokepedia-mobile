import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import 'models/portfolio_value.dart';

/// The collection-worth history behind the Beranda chart.
///
/// Reads `collection_value_snapshots`, one row per collection per day, written
/// by the `snapshot_collection_values` cron at 00:20 UTC.
///
/// A collection holding no cards gets no row at all, so a gap in the series
/// means "no snapshot", never "unchanged" — which is why a missing day is
/// left as a gap rather than carried forward from the day before.
///
/// This used to be derived on the device from `price_history`: pull every
/// daily close for every held card, carry the last known price across days a
/// card didn't trade, and sum. Two things were wrong with that. `price_history`
/// only gains a row on a day a card actually *sells*, so an individual
/// collection produced an empty or single-point series — it holds three rows
/// today. And the derivation applied *current* holdings to past prices, so
/// buying a card retroactively rewrote last month's chart. A snapshot records
/// what the user actually held that day.
///
/// `collection_value_snapshots_select_own` scopes the table to its owner, so
/// this runs on the user's own session and needs no user id passed in — but
/// the collection does have to be named, since the owner now has a line per
/// collection rather than one for the account.
class PortfolioValueRepository {
  PortfolioValueRepository(this._client);

  final SupabaseClient _client;

  /// A ceiling on days pulled. MAX has no lower bound, and a long-lived
  /// account should not hand the chart ten years of rows to draw.
  static const _maxDays = 400;

  /// Daily portfolio value over [range].
  ///
  /// Returns empty when the account has no snapshots yet — a new account, or
  /// one whose first nightly run hasn't happened. The chart shows its own
  /// message for that rather than a flat line at zero, which would read as
  /// "your collection is worthless".
  Future<List<PortfolioValuePoint>> fetchValueSeries({
    required PortfolioRange range,
    required String collectionId,
  }) async {
    final days = range.days;
    var query = _client
        .from('collection_value_snapshots')
        .select('snapshot_on, total_value')
        // Without this the series interleaves every collection's rows and
        // `_maxDays` truncates a long range partway through one of them.
        .eq('collection_id', collectionId);

    if (days != null) {
      final from = DateTime.now().toUtc().subtract(Duration(days: days));
      query = query.gte('snapshot_on', _isoDay(from));
    }

    final rows = await query
        .order('snapshot_on', ascending: true)
        .limit(_maxDays);

    final series = <PortfolioValuePoint>[];
    for (final row in rows) {
      final day = DateTime.tryParse(row['snapshot_on'] as String? ?? '');
      final value = (row['total_value'] as num?)?.round();
      if (day == null || value == null) continue;
      series.add(PortfolioValuePoint(day: _dateOnly(day), value: value));
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
  (ref) => PortfolioValueRepository(ref.watch(supabaseClientProvider)),
);
