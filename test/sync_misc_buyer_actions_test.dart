import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/account/repository/models/buyer_action_counts.dart';

void main() {
  group('BuyerActionCounts.fromJson', () {
    test('reads every bucket and derives the Pesanan count', () {
      final counts = BuyerActionCounts.fromJson({
        'unpaid': 2,
        'arrived': 1,
        'proposals': 4,
        'disputes': 1,
        'total': 8,
      });
      expect(counts.unpaid, 2);
      expect(counts.arrived, 1);
      expect(counts.proposals, 4);
      expect(counts.disputes, 1);
      expect(counts.total, 8);
      expect(counts.orders, 4);
    });

    test('non-numeric fields read as zero, like web parseBreakdown', () {
      final counts = BuyerActionCounts.fromJson({
        'unpaid': '3',
        'arrived': null,
        'proposals': 1.0,
        'total': 1,
      });
      expect(counts.unpaid, 0);
      expect(counts.arrived, 0);
      expect(counts.proposals, 1);
      expect(counts.disputes, 0);
      expect(counts.orders, 0);
      expect(counts.total, 1);
    });

    test('a payload that is not an object is nothing to do', () {
      for (final raw in [null, 5, 'x', <Object>[]]) {
        final counts = BuyerActionCounts.fromJson(raw);
        expect(counts.total, 0);
        expect(counts.orders, 0);
      }
    });
  });
}
