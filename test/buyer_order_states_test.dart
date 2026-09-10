import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';
import 'package:pokepedia_mobile/features/orders/utils/order_status_display.dart';

/// Mirrors the shape `_orderColumns` selects, so the states are exercised
/// against a row the repository could actually return.
Map<String, dynamic> _row({
  String orderStatus = 'awaiting_shipment',
  String itemStatus = 'in_escrow',
  String? settlementStatus = 'awaiting_shipment',
  String? paidAt = '2026-08-20T09:00:00+00:00',
  String? paymentDeadline,
  String? cancelStatus,
  String? disputeStatus,
  String? shipmentStatus,
  String? shippedAt,
  String? deliveredAt,
  String? originCollectionMethod,
  String courier = 'jne',
  List<Map<String, dynamic>>? statusHistory,
}) => {
  'id': 1,
  'slug': 'order-1',
  'order_number': 'ORD-001',
  'status': orderStatus,
  'created_at': '2026-08-19T09:00:00+00:00',
  'seller_id': 'seller',
  'buyer_id': 'buyer',
  'order_items': [
    {
      'id': 11,
      'slug': 'item-1',
      'order_number': 'ORD-001',
      'card_id': 7,
      'matched_quantity': 1,
      'match_price': 100000,
      'status': itemStatus,
      'created_at': '2026-08-19T09:00:00+00:00',
      'cards': {
        'id': 7,
        'name_id': 'Charizard ex',
        'expansion_code': 'SV2a',
        'collector_number': '201/165',
        'rarity': 'SAR',
        'category': 'Pokemon',
        'language': 'id',
        'variant': 'normal',
        'details': <String, dynamic>{},
      },
      'settlements': {
        'condition': 'NM',
        'shipping_cost': 20000,
        'status': settlementStatus,
        'paid_at': paidAt,
        'payment_deadline': paymentDeadline,
        'cancel_status': cancelStatus,
        'cancel_reason': null,
      },
      'disputes': disputeStatus == null
          ? <Map<String, dynamic>>[]
          : [
              {'slug': 'dispute-1', 'current_status': disputeStatus},
            ],
    },
  ],
  'shipments': {
    'tracking_number': null,
    'courier': courier,
    'status': shipmentStatus,
    'shipped_at': shippedAt,
    'delivered_at': deliveredAt,
    'shipment_deadline': null,
    'biteship_order_id': null,
    'biteship_book_error': null,
    'origin_collection_method': originCollectionMethod,
    'status_history': statusHistory,
  },
};

OrderModel _order(Map<String, dynamic> row) =>
    OrderModel.fromRow(row, storeName: 'Toko');

final _now = DateTime.parse('2026-08-25T12:00:00Z');

void main() {
  group('showTracking', () {
    test('a dispatched parcel shows tracking even without a resi', () {
      // The gate mobile used to have (`trackingNumber != null`) hid the
      // section exactly when the buyer wanted it.
      final s = BuyerOrderStates(
        _order(_row(settlementStatus: 'shipped', shipmentStatus: 'shipped')),
        now: _now,
      );
      expect(s.showTracking, isTrue);
    });

    test('a parcel still being packed does not', () {
      final s = BuyerOrderStates(
        _order(_row(shipmentStatus: 'awaiting_shipment')),
        now: _now,
      );
      expect(s.showTracking, isFalse);
      expect(s.preparing, isTrue);
    });

    test('courier history alone is enough', () {
      final s = BuyerOrderStates(
        _order(
          _row(
            shipmentStatus: 'awaiting_pickup',
            statusHistory: [
              {'status': 'picked', 'at': '2026-08-24T09:00:00+00:00'},
            ],
          ),
        ),
        now: _now,
      );
      expect(s.showTracking, isTrue);
    });
  });

  group('reporting a complaint', () {
    test('not offered before dispatch', () {
      final s = BuyerOrderStates(
        _order(_row(shipmentStatus: 'awaiting_shipment')),
        now: _now,
      );
      expect(s.showReport, isFalse);
    });

    test('offered but inactive within a day of dispatch', () {
      // `canReportNotReceived`: a parcel that left this morning can't be
      // reported missing this afternoon.
      final s = BuyerOrderStates(
        _order(
          _row(
            settlementStatus: 'shipped',
            shipmentStatus: 'shipped',
            shippedAt: '2026-08-25T06:00:00+00:00',
          ),
        ),
        now: _now,
      );
      expect(s.showReport, isTrue);
      expect(s.reportActive, isFalse);
    });

    test('active once the 24h window has passed', () {
      final s = BuyerOrderStates(
        _order(
          _row(
            settlementStatus: 'shipped',
            shipmentStatus: 'shipped',
            shippedAt: '2026-08-23T06:00:00+00:00',
          ),
        ),
        now: _now,
      );
      expect(s.reportActive, isTrue);
    });

    test('active immediately once delivered', () {
      final s = BuyerOrderStates(
        _order(
          _row(
            settlementStatus: 'shipped',
            shipmentStatus: 'received',
            shippedAt: '2026-08-25T06:00:00+00:00',
          ),
        ),
        now: _now,
      );
      expect(s.reportActive, isTrue);
    });

    test('withdrawn once a complaint is already open', () {
      final s = BuyerOrderStates(
        _order(
          _row(
            settlementStatus: 'shipped',
            shipmentStatus: 'shipped',
            disputeStatus: 'opened',
          ),
        ),
        now: _now,
      );
      expect(s.disputeOpen, isTrue);
      // The old page offered "Ajukan Sengketa" on top of an open dispute.
      expect(s.showReport, isFalse);
    });
  });

  group('other states', () {
    test('a cancellation waiting on the seller is surfaced', () {
      final s = BuyerOrderStates(
        _order(_row(cancelStatus: 'pending_seller')),
        now: _now,
      );
      expect(s.cancelPending, isTrue);
    });

    test('an unpaid order is not "being prepared"', () {
      final s = BuyerOrderStates(
        _order(_row(settlementStatus: 'awaiting_payment', paidAt: null)),
        now: _now,
      );
      expect(s.isUnpaid, isTrue);
      expect(s.preparing, isFalse);
    });
  });
  group('confirming receipt', () {
    test('delivered by the courier lets the buyer confirm', () {
      final order = _order(
        _row(shipmentStatus: 'shipped', deliveredAt: '2026-08-24T09:00:00Z'),
      );
      expect(order.canConfirmReceiptAt(_now), isTrue);
    });

    test('still confirmable once the shipment reads received', () {
      // The old rule demanded shipmentStatus == 'shipped', so the button
      // vanished exactly when the parcel arrived.
      final order = _order(_row(shipmentStatus: 'received'));
      expect(order.canConfirmReceiptAt(_now), isTrue);
    });

    test('in transit, with nothing delivered, it is not', () {
      final order = _order(
        _row(shipmentStatus: 'shipped', shippedAt: '2026-08-25T06:00:00Z'),
      );
      expect(order.canConfirmReceiptAt(_now), isFalse);
    });

    test('an untrackable manual courier unlocks a day after dispatch', () {
      // No courier history is ever coming for these, so web lets the buyer
      // confirm on a timer instead of waiting forever.
      final order = _order(
        _row(
          shipmentStatus: 'shipped',
          shippedAt: '2026-08-23T06:00:00Z',
          originCollectionMethod: 'manual',
          courier: 'jne',
        ),
      );
      expect(order.isUntrackableManual, isTrue);
      expect(order.canConfirmReceiptAt(_now), isTrue);
    });

    test('but not within that first day', () {
      final order = _order(
        _row(
          shipmentStatus: 'shipped',
          shippedAt: '2026-08-25T06:00:00Z',
          originCollectionMethod: 'manual',
        ),
      );
      expect(order.canConfirmReceiptAt(_now), isFalse);
    });

    test('a trackable courier gets no such timer', () {
      final order = _order(
        _row(
          shipmentStatus: 'shipped',
          shippedAt: '2026-08-23T06:00:00Z',
          originCollectionMethod: 'manual',
          courier: 'anteraja',
        ),
      );
      expect(order.isUntrackableManual, isFalse);
      expect(order.canConfirmReceiptAt(_now), isFalse);
    });

    test('an unpaid order can never be confirmed', () {
      final order = _order(
        _row(
          settlementStatus: 'awaiting_payment',
          paidAt: null,
          shipmentStatus: 'received',
        ),
      );
      expect(order.canConfirmReceiptAt(_now), isFalse);
    });
  });
  group('terminal stages', () {
    test('a completed order offers no complaint and no confirm hint', () {
      // `isShipped` used to read the shipment, which stays `received` after
      // delivery — so a finished order kept offering both.
      final s = BuyerOrderStates(
        _order(
          _row(
            orderStatus: 'completed',
            itemStatus: 'completed',
            settlementStatus: 'released',
            shipmentStatus: 'received',
            deliveredAt: '2026-08-24T09:00:00Z',
          ),
        ),
        now: _now,
      );
      expect(s.isShipped, isFalse);
      expect(s.showReport, isFalse);
      expect(s.isCompleted, isTrue);
      // Tracking stays available on a finished order, as on web.
      expect(s.showTracking, isTrue);
    });

    test('a cancelled order is not "being prepared"', () {
      // No shipment row exists, and null used to count as preparing — so a
      // cancelled order told the buyer the seller was packing it.
      final s = BuyerOrderStates(
        _order(
          _row(
            orderStatus: 'cancelled',
            itemStatus: 'cancelled',
            settlementStatus: 'refunded',
            shipmentStatus: null,
          ),
        ),
        now: _now,
      );
      expect(s.preparing, isFalse);
      expect(s.showReport, isFalse);
      expect(s.showTracking, isFalse);
    });

    test('an order actually being packed still says so', () {
      final s = BuyerOrderStates(
        _order(
          _row(
            settlementStatus: 'awaiting_shipment',
            shipmentStatus: 'awaiting_shipment',
          ),
        ),
        now: _now,
      );
      expect(s.preparing, isTrue);
    });

    test('a shipped settlement drives the shipped stage', () {
      final s = BuyerOrderStates(
        _order(_row(settlementStatus: 'shipped', shipmentStatus: 'shipped')),
        now: _now,
      );
      expect(s.isShipped, isTrue);
      expect(s.showReport, isTrue);
      expect(s.preparing, isFalse);
    });
  });
  group('after confirming receipt', () {
    test('the confirm block is gone once the settlement releases', () {
      // The bug: `canConfirm` stays true forever once a delivery timestamp
      // exists, so a button gated on it alone survived its own tap. Web
      // nests the whole block behind `{isShipped && …}`, and confirming
      // moves the settlement off `shipped`.
      final confirmed = _order(
        _row(
          orderStatus: 'completed',
          itemStatus: 'completed',
          settlementStatus: 'released',
          shipmentStatus: 'received',
          deliveredAt: '2026-08-24T09:00:00Z',
        ),
      );
      final s = BuyerOrderStates(confirmed, now: _now);

      // Still "confirmable" in isolation — which is why the gate matters.
      expect(confirmed.canConfirmReceiptAt(_now), isTrue);
      expect(s.isShipped, isFalse, reason: 'the block must not render');
      // And tracking stays, so the buyer can still see the trail.
      expect(s.showTracking, isTrue);
    });

    test('before confirming, the block is there', () {
      final s = BuyerOrderStates(
        _order(
          _row(
            settlementStatus: 'shipped',
            shipmentStatus: 'received',
            deliveredAt: '2026-08-24T09:00:00Z',
          ),
        ),
        now: _now,
      );
      expect(s.isShipped, isTrue);
      expect(s.canConfirm, isTrue);
    });

    test('a completed order keeps no confirm affordance at all', () {
      final s = BuyerOrderStates(
        _order(
          _row(
            orderStatus: 'completed',
            itemStatus: 'completed',
            settlementStatus: 'completed',
            shipmentStatus: 'received',
          ),
        ),
        now: _now,
      );
      expect(s.isShipped, isFalse);
      expect(s.showReport, isFalse);
    });
  });

  group('Batalkan Pesanan', () {
    test('offered while the seller has not dispatched', () {
      final s = BuyerOrderStates(
        _order(
          _row(
            settlementStatus: 'awaiting_shipment',
            shipmentStatus: 'awaiting_shipment',
          ),
        ),
        now: _now,
      );
      expect(s.canRequestCancel, isTrue);
      expect(s.showDisabledCancel, isFalse);
    });

    test('a shipment row that does not exist yet still allows it', () {
      // No booking has been made, so there is nothing to call off.
      final s = BuyerOrderStates(
        _order(_row(settlementStatus: 'awaiting_shipment')),
        now: _now,
      );
      expect(s.canRequestCancel, isTrue);
    });

    test('withdrawn once a resi exists, but still shown', () {
      // Web keeps the button on screen disabled rather than removing it —
      // `showDisabledCancel` — so the option reads as spent, not absent.
      final s = BuyerOrderStates(
        _order(
          _row(settlementStatus: 'awaiting_shipment', shipmentStatus: 'shipped'),
        ),
        now: _now,
      );
      expect(s.canRequestCancel, isFalse);
      expect(s.showDisabledCancel, isTrue);
    });

    test('gone once a request is already pending', () {
      final s = BuyerOrderStates(
        _order(
          _row(
            settlementStatus: 'awaiting_shipment',
            shipmentStatus: 'awaiting_shipment',
            cancelStatus: 'pending_seller',
          ),
        ),
        now: _now,
      );
      expect(s.cancelPending, isTrue);
      expect(s.canRequestCancel, isFalse);
      expect(s.showDisabledCancel, isFalse);
    });

    test('never offered before payment', () {
      final s = BuyerOrderStates(
        _order(_row(settlementStatus: 'awaiting_payment', paidAt: null)),
        now: _now,
      );
      expect(s.canRequestCancel, isFalse);
      expect(s.showDisabledCancel, isFalse);
    });

    test('never offered once shipped, completed or already cancelled', () {
      final shipped = BuyerOrderStates(
        _order(_row(settlementStatus: 'shipped', shipmentStatus: 'shipped')),
        now: _now,
      );
      expect(shipped.canRequestCancel, isFalse);
      expect(shipped.showDisabledCancel, isFalse);

      final done = BuyerOrderStates(
        _order(
          _row(
            orderStatus: 'completed',
            itemStatus: 'completed',
            settlementStatus: 'released',
            shipmentStatus: 'received',
          ),
        ),
        now: _now,
      );
      expect(done.canRequestCancel, isFalse);

      final cancelled = BuyerOrderStates(
        _order(
          _row(
            orderStatus: 'cancelled',
            itemStatus: 'cancelled',
            settlementStatus: 'refunded',
            shipmentStatus: null,
          ),
        ),
        now: _now,
      );
      expect(cancelled.canRequestCancel, isFalse);
      expect(cancelled.showDisabledCancel, isFalse);
    });
  });
}
