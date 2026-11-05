import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/my_reliability.dart';

/// Ports web's `describeReliability` / `topSellerRequirements` checks, read
/// from the shape `get_my_reliability` returns.
void main() {
  Map<String, dynamic> window({
    int paid = 0,
    int completed = 0,
    int cancels = 0,
    int lost = 0,
    num? median,
  }) => {
    'paid_orders': paid,
    'completed_orders': completed,
    'seller_cancels': cancels,
    'disputes_lost': lost,
    'shipped_orders': completed,
    'median_ship_hours': median,
  };

  test('the RPC error answer reads as nothing', () {
    expect(MyReliability.fromJson({'error': 'unauthorized'}), isNull);
    expect(MyReliability.fromJson(null), isNull);
  });

  test('a new seller: no completion share yet, every gap named', () {
    final r = MyReliability.fromJson({
      'window_90d': window(paid: 2, completed: 2),
      'window_30d': window(paid: 2, completed: 2),
      'top_rated': false,
      'negative_rating_30d': false,
      'failures': [],
    })!;
    expect(r.completionPct, isNull, reason: 'under 5 paid orders');
    final reqs = r.topSellerRequirements;
    expect(reqs.map((q) => q.met), [false, true, false, true]);
    expect(reqs[0].detail, 'Kurang 18 pesanan lagi');
    expect(reqs[2].detail, 'Belum ada pesanan terkirim');
  });

  test('an established seller over the cancel limit', () {
    final r = MyReliability.fromJson({
      'window_90d': window(paid: 20, completed: 16, cancels: 3, median: 20.2),
      'window_30d': window(paid: 25, completed: 22, cancels: 2, median: 23.5),
      'top_rated': false,
      'negative_rating_30d': true,
      'failures': [
        {
          'order_number': 'ORD-261020-AB12C',
          'paid_at': '2026-10-20T00:00:00Z',
          'fault': 'cancelled',
          'item_slug': '0b6f4a8e-0000-4000-8000-000000000001',
        },
      ],
    })!;
    expect(r.completionPct, 84); // 16 of 19 finished, floored
    expect(r.cancelPct, 15);
    expect(r.belowStandard, isTrue);
    expect(r.medianShipHours, 21);
    final reqs = r.topSellerRequirements;
    expect(reqs.map((q) => q.met), [true, false, true, false]);
    expect(reqs[1].detail, 'Rate batal 8%');
    expect(reqs[3].detail, 'Ada rating negatif');
    expect(r.failures.single.faultLabel, 'Dibatalkan penjual');
  });
}
