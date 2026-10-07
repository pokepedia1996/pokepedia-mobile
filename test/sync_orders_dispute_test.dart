import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/open_dispute.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';
import 'package:pokepedia_mobile/features/orders/utils/dispute_reasons.dart';

Map<String, dynamic> _item({
  int id = 11,
  String slug = 'item-1',
  String settlementStatus = 'shipped',
  List<Map<String, dynamic>> disputes = const [],
}) => {
  'id': id,
  'slug': slug,
  'order_number': 'ord-1',
  'card_id': 7,
  'matched_quantity': 2,
  'match_price': 25000,
  'status': 'shipped',
  'created_at': '2026-10-01T09:00:00+00:00',
  'cards': null,
  'settlements': {
    'slug': 'settlement-$id',
    'status': settlementStatus,
    'paid_at': '2026-10-01T09:00:00+00:00',
  },
  'disputes': disputes,
};

OrderModel _order(
  List<Map<String, dynamic>> items, {
  String shipmentStatus = 'shipped',
  String? deliveredAt,
  String shippedAt = '2026-10-01T09:00:00+00:00',
}) => OrderModel.fromRow({
  'id': 1,
  'slug': 'order-1',
  'order_number': 'ord-1',
  'status': 'shipped',
  'created_at': '2026-10-01T09:00:00+00:00',
  'seller_id': 'seller',
  'buyer_id': 'buyer',
  'order_items': items,
  'shipments': {
    'slug': 'shipment-1',
    'courier_code': 'jnt',
    'origin_collection_method': 'pickup',
    'status': shipmentStatus,
    'shipped_at': shippedAt,
    'delivered_at': deliveredAt,
  },
}, storeName: 'Toko');

void main() {
  test('reason codes and labels match web', () {
    expect(DisputeReason.values.map((r) => r.raw), [
      'not_received',
      'damaged',
      'not_as_described',
      'short',
    ]);
    expect(DisputeReason.notReceived.label, 'Barang tidak diterima');
    expect(DisputeReason.notAsDescribed.label, 'Barang tidak sesuai');
    expect(DisputeReason.short.optionLabel, 'Kurang/tidak lengkap');
  });

  group('openDisputeEligibility', () {
    final now = DateTime.parse('2026-10-03T09:00:00Z');

    test('in transit inside the INR window: nothing is openable', () {
      final eligibility = openDisputeEligibility(
        _order([_item()], shippedAt: '2026-10-03T08:00:00+00:00'),
        now: now,
      );
      expect(eligibility.canNotReceived, isFalse);
      expect(eligibility.canSnad, isFalse);
    });

    test('in transit past the INR window: only not-received', () {
      final eligibility = openDisputeEligibility(_order([_item()]), now: now);
      expect(eligibility.canNotReceived, isTrue);
      expect(eligibility.canSnad, isFalse);
      expect(eligibility.isEnabled(DisputeReason.damaged), isFalse);
    });

    test('delivered: SNAD covers shipped lines without a live dispute', () {
      final eligibility = openDisputeEligibility(
        _order(
          [
            _item(),
            _item(
              id: 12,
              slug: 'item-2',
              disputes: [
                {
                  'slug': 'd-1',
                  'current_status': 'awaiting_seller',
                  'reason_category': 'damaged',
                },
              ],
            ),
            _item(id: 13, slug: 'item-3', settlementStatus: 'completed'),
          ],
          shipmentStatus: 'received',
          deliveredAt: '2026-10-02T09:00:00+00:00',
        ),
        now: now,
      );
      expect(eligibility.snadItems.map((i) => i.slug), ['item-1']);
      expect(eligibility.canNotReceived, isTrue);
    });

    test('a live not-received complaint on every line blocks another', () {
      final live = [
        {
          'slug': 'd-1',
          'current_status': 'awaiting_seller',
          'reason_category': 'not_received',
        },
      ];
      final eligibility = openDisputeEligibility(
        _order([_item(disputes: live)]),
        now: now,
      );
      expect(eligibility.canNotReceived, isFalse);
    });
  });

  group('OpenDisputeEntry.toJson', () {
    test('short forces refund_only and sends a quantity per item', () {
      final json = const OpenDisputeEntry(
        reason: DisputeReason.short,
        itemSlugs: ['a', 'b'],
        detail: '  kurang satu  ',
        photoUrls: [
          'https://x/storage/v1/object/public/dispute-evidence/s/p.jpg',
        ],
        shortQuantity: {'a': 2},
        requestedResolution: DisputeResolution.returnRefund,
      ).toJson();
      expect(json['reason'], 'short');
      expect(json['detail'], 'kurang satu');
      expect(json['shortQuantity'], {'a': 2, 'b': 1});
      expect(json['requestedResolution'], 'refund_only');
      expect(json.containsKey('videoUrl'), isFalse);
    });

    test('damaged omits shortQuantity and carries the chosen resolution', () {
      final json = const OpenDisputeEntry(
        reason: DisputeReason.damaged,
        itemSlugs: ['a'],
        detail: 'penyok',
        photoUrls: ['u'],
        videoUrl: 'https://drive.google.com/x',
        requestedResolution: DisputeResolution.returnRefund,
      ).toJson();
      expect(json.containsKey('shortQuantity'), isFalse);
      expect(json['requestedResolution'], 'return_refund');
      expect(json['videoUrl'], 'https://drive.google.com/x');
    });
  });

  test('isHttpsUrl', () {
    expect(isHttpsUrl('https://youtu.be/x'), isTrue);
    expect(isHttpsUrl('http://youtu.be/x'), isFalse);
    expect(isHttpsUrl('youtu.be/x'), isFalse);
  });
}
