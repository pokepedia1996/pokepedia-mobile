import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_dashboard.dart';

/// `get_seller_performance` emits one `daily_gmv` entry per day that had a
/// sale — quiet days are absent, not zero — and stamps them `YYYY-MM-DD` off
/// `date_trunc('day', completed_at)`. These pin the arithmetic that reads
/// those sparse rows back.
DailyGmv _day(String day, int gmv) => DailyGmv(day: day, gmv: gmv);

void main() {
  group('computeSummary', () {
    // Fixed "now" so the 60-day walk is deterministic.
    final now = DateTime.utc(2026, 8, 20, 9, 30);

    test('sums the rolling windows off sparse rows', () {
      final summary = computeSummary([
        _day('2026-08-20', 50000), // today
        _day('2026-08-18', 25000), // within 7
        _day('2026-08-01', 10000), // within 30
        _day('2026-07-10', 90000), // the previous 30
      ], now: now);

      expect(summary.today, 50000);
      expect(summary.last7, 75000);
      expect(summary.last30, 85000);
      expect(summary.last90, 175000);
    });

    test('delta30 compares the last 30 days with the 30 before', () {
      final summary = computeSummary([
        _day('2026-08-15', 150), // last 30
        _day('2026-07-15', 100), // prior 30
      ], now: now);

      expect(summary.delta30, closeTo(50, 0.001));
    });

    test('a first-ever sale reads as +100%, not infinity', () {
      final summary = computeSummary([_day('2026-08-15', 1000)], now: now);
      expect(summary.delta30, 100);
    });

    test('no sales at all is flat, not a divide by zero', () {
      final summary = computeSummary(const [], now: now);
      expect(summary.delta30, 0);
      expect(summary.last90, 0);
      expect(summary.today, 0);
    });

    test('matches days in UTC, as the RPC stamps them', () {
      // 06:00 on the 20th in Jakarta (UTC+7) is still the 19th in UTC — the
      // walk must not look up a day the RPC never emitted.
      final jakartaMorning = DateTime.utc(2026, 8, 19, 23, 0);
      final summary = computeSummary([
        _day('2026-08-19', 7000),
        _day('2026-08-20', 9000),
      ], now: jakartaMorning);

      expect(summary.today, 7000);
    });
  });

  group('percentDelta', () {
    test('reports growth and decline', () {
      expect(percentDelta(current: 150, previous: 100), closeTo(50, 0.001));
      expect(percentDelta(current: 50, previous: 100), closeTo(-50, 0.001));
    });

    test('treats a zero baseline as new, and zero-to-zero as flat', () {
      expect(percentDelta(current: 10, previous: 0), 100);
      expect(percentDelta(current: 0, previous: 0), 0);
    });
  });

  group('DashboardPayload.fromRow', () {
    test('maps a performance row', () {
      final payload = DashboardPayload.fromRow({
        'gmv': 1250000,
        'prev_gmv': 1000000,
        'orders_count': 12,
        'prev_orders_count': 10,
        'items_count': 30,
        'prev_items_count': 25,
        'unique_buyers': 8,
        'prev_unique_buyers': 9,
        'daily_gmv': [
          {'day': '2026-08-19', 'gmv': 250000},
          {'day': '2026-08-20', 'gmv': 1000000},
        ],
        'dispute_rate': 0.02,
        'cancel_rate': 0.01,
        'on_time_ship_rate': 0.98,
        'awaiting_payment_count': 1,
        'to_ship_count': 3,
        'in_transit_count': 2,
        'arrived_count': 0,
        'completed_count': 20,
        'cancel_requests_count': 1,
        'cancelled_count': 0,
        'disputes_open_count': 2,
        'wallet_balance': 4200000,
      }, 30);

      expect(payload.performance.gmv, 1250000);
      expect(payload.performance.window, 30);
      expect(payload.performance.dailyGmv, hasLength(2));
      expect(payload.performance.dailyGmv.last.gmv, 1000000);
      expect(payload.kpi.toShip, 3);
      expect(payload.kpi.disputesOpen, 2);
      expect(payload.walletBalance, 4200000);
      expect(payload.health.onTimeShipRate, closeTo(0.98, 0.0001));
    });

    test('accepts the bigint-as-string form PostgREST can emit', () {
      final payload = DashboardPayload.fromRow({
        'gmv': '1250000',
        'orders_count': '12',
        'daily_gmv': [
          {'day': '2026-08-20', 'gmv': '99000'},
        ],
        'wallet_balance': '4200000',
      }, 7);

      expect(payload.performance.gmv, 1250000);
      expect(payload.performance.orders, 12);
      expect(payload.performance.dailyGmv.single.gmv, 99000);
      expect(payload.walletBalance, 4200000);
    });

    test('survives a missing or malformed daily_gmv', () {
      final payload = DashboardPayload.fromRow({
        'gmv': 10,
        'daily_gmv': ['nonsense', 42],
      }, 30);
      expect(payload.performance.dailyGmv, isEmpty);
    });
  });
}
