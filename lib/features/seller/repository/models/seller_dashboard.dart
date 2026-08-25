/// One day of net revenue, as `get_seller_performance` returns it in
/// `daily_gmv`.
class DailyGmv {
  const DailyGmv({required this.day, required this.gmv});

  /// `YYYY-MM-DD`.
  final String day;
  final int gmv;
}

/// The "Penting hari ini" counters. Ports `DashboardKpi`.
class DashboardKpi {
  const DashboardKpi({
    this.awaitingPayment = 0,
    this.toShip = 0,
    this.inTransit = 0,
    this.arrived = 0,
    this.completed = 0,
    this.cancelRequests = 0,
    this.cancelled = 0,
    this.disputesOpen = 0,
  });

  final int awaitingPayment;
  final int toShip;
  final int inTransit;
  final int arrived;
  final int completed;
  final int cancelRequests;
  final int cancelled;
  final int disputesOpen;
}

/// Ports `DashboardPerformance` — the window's totals, each paired with the
/// preceding window of the same length so the cards can show a delta.
class DashboardPerformance {
  const DashboardPerformance({
    required this.window,
    this.gmv = 0,
    this.prevGmv = 0,
    this.orders = 0,
    this.prevOrders = 0,
    this.items = 0,
    this.prevItems = 0,
    this.uniqueBuyers = 0,
    this.prevUniqueBuyers = 0,
    this.dailyGmv = const [],
  });

  final int window;
  final int gmv;
  final int prevGmv;
  final int orders;
  final int prevOrders;
  final int items;
  final int prevItems;
  final int uniqueBuyers;
  final int prevUniqueBuyers;
  final List<DailyGmv> dailyGmv;
}

/// Ports `DashboardHealth`.
class DashboardHealth {
  const DashboardHealth({
    this.disputeRate = 0,
    this.cancelRate = 0,
    this.onTimeShipRate = 1,
  });

  final double disputeRate;
  final double cancelRate;
  final double onTimeShipRate;
}

/// Ports `DashboardSummary` — the rolling revenue rows under the chart.
class DashboardSummary {
  const DashboardSummary({
    this.today = 0,
    this.last7 = 0,
    this.last30 = 0,
    this.last90 = 0,
    this.delta30 = 0,
  });

  final int today;
  final int last7;
  final int last30;
  final int last90;

  /// Percent change of the last 30 days against the 30 before them.
  final double delta30;
}

/// Ports `DashboardPayload`.
class DashboardPayload {
  const DashboardPayload({
    required this.kpi,
    required this.performance,
    required this.health,
    required this.summary,
    required this.walletBalance,
  });

  final DashboardKpi kpi;
  final DashboardPerformance performance;
  final DashboardHealth health;
  final DashboardSummary summary;
  final int walletBalance;

  DashboardPayload copyWith({DashboardSummary? summary}) => DashboardPayload(
    kpi: kpi,
    performance: performance,
    health: health,
    summary: summary ?? this.summary,
    walletBalance: walletBalance,
  );

  /// Ports `emptyDashboardPayload` — what the page shows when the RPC fails,
  /// so the layout stays put instead of collapsing to an error screen.
  factory DashboardPayload.empty(int windowDays) => DashboardPayload(
    kpi: const DashboardKpi(),
    performance: DashboardPerformance(window: windowDays),
    health: const DashboardHealth(),
    summary: const DashboardSummary(),
    walletBalance: 0,
  );

  /// Ports `mapRowToPayload` over one `get_seller_performance` row.
  factory DashboardPayload.fromRow(
    Map<String, dynamic> row,
    int windowDays,
  ) {
    int asInt(Object? v) => switch (v) {
      final int i => i,
      final num n => n.round(),
      final String s => num.tryParse(s)?.round() ?? 0,
      _ => 0,
    };
    double asDouble(Object? v) => switch (v) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

    final daily = <DailyGmv>[];
    final rawDaily = row['daily_gmv'];
    if (rawDaily is List) {
      for (final entry in rawDaily) {
        if (entry is! Map) continue;
        final day = entry['day'];
        if (day is! String) continue;
        daily.add(DailyGmv(day: day, gmv: asInt(entry['gmv'])));
      }
    }

    return DashboardPayload(
      kpi: DashboardKpi(
        awaitingPayment: asInt(row['awaiting_payment_count']),
        toShip: asInt(row['to_ship_count']),
        inTransit: asInt(row['in_transit_count']),
        arrived: asInt(row['arrived_count']),
        completed: asInt(row['completed_count']),
        cancelRequests: asInt(row['cancel_requests_count']),
        cancelled: asInt(row['cancelled_count']),
        disputesOpen: asInt(row['disputes_open_count']),
      ),
      performance: DashboardPerformance(
        window: windowDays,
        gmv: asInt(row['gmv']),
        prevGmv: asInt(row['prev_gmv']),
        orders: asInt(row['orders_count']),
        prevOrders: asInt(row['prev_orders_count']),
        items: asInt(row['items_count']),
        prevItems: asInt(row['prev_items_count']),
        uniqueBuyers: asInt(row['unique_buyers']),
        prevUniqueBuyers: asInt(row['prev_unique_buyers']),
        dailyGmv: daily,
      ),
      health: DashboardHealth(
        disputeRate: asDouble(row['dispute_rate']),
        cancelRate: asDouble(row['cancel_rate']),
        onTimeShipRate: asDouble(row['on_time_ship_rate']),
      ),
      summary: const DashboardSummary(),
      walletBalance: asInt(row['wallet_balance']),
    );
  }
}

/// Ports `computeSummary`, which the web feeds with the 90-day window: the
/// rolling totals under the chart, plus how the last 30 days compare with
/// the 30 before them.
///
/// Days are matched on the `YYYY-MM-DD` strings the RPC emits, and those are
/// produced in UTC — so the walk back from today uses UTC too, otherwise
/// a device east of Greenwich would look up tomorrow's key and read 0.
DashboardSummary computeSummary(List<DailyGmv> daily90, {DateTime? now}) {
  final today = (now ?? DateTime.now()).toUtc();
  final byDay = {for (final d in daily90) d.day: d.gmv};

  String isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  var last7 = 0;
  var last30 = 0;
  var prev30 = 0;

  for (var i = 0; i < 60; i++) {
    final value = byDay[isoDay(today.subtract(Duration(days: i)))] ?? 0;
    if (i < 7) last7 += value;
    if (i < 30) {
      last30 += value;
    } else {
      prev30 += value;
    }
  }

  final last90 = daily90.fold(0, (sum, d) => sum + d.gmv);

  final delta30 = prev30 == 0
      ? (last30 == 0 ? 0.0 : 100.0)
      : ((last30 - prev30) / prev30) * 100;

  return DashboardSummary(
    today: byDay[isoDay(today)] ?? 0,
    last7: last7,
    last30: last30,
    last90: last90,
    delta30: delta30,
  );
}

/// Percent change used by every metric card. Ports `MetricCard`'s inline
/// delta: no previous window means "new", not "infinite".
double percentDelta({required num current, required num previous}) {
  if (previous == 0) return current == 0 ? 0 : 100;
  return ((current - previous) / previous) * 100;
}

/// Ports `WINDOW_OPTIONS`.
enum SellerWindow {
  week(7, '7 hari'),
  month(30, '30 hari'),
  quarter(90, '90 hari');

  const SellerWindow(this.days, this.label);

  final int days;
  final String label;
}
