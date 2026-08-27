import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/pending_checkout.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/seller_order.dart';

Map<String, dynamic> _orderRow({
  String slug = 'order-1',
  String itemStatus = 'in_escrow',
  String? settlementStatus = 'in_escrow',
  String? paidAt = '2026-08-20T09:00:00+00:00',
  String? cancelStatus,
  String? disputeStatus,
  String? shipmentStatus,
  String? shipmentDeadline,
  String? biteshipOrderId,
  String? biteshipBookError,
  String? originCollectionMethod,
  List<Map<String, dynamic>>? statusHistory,
  int price = 100000,
  int quantity = 1,
  int shippingCost = 20000,
  String createdAt = '2026-08-19T09:00:00+00:00',
}) {
  return {
    'id': 1,
    'slug': slug,
    'order_number': 'ORD-001',
    'status': 'awaiting_shipment',
    'created_at': createdAt,
    'seller_id': 'seller',
    'buyer_id': 'buyer',
    'order_items': [
      {
        'slug': 'item-1',
        'order_number': 'ORD-001',
        'card_id': 7,
        'matched_quantity': quantity,
        'match_price': price,
        'status': itemStatus,
        'created_at': createdAt,
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
          'shipping_cost': shippingCost,
          'status': settlementStatus,
          'paid_at': paidAt,
          'payment_deadline': null,
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
    'shipments': shipmentStatus == null && statusHistory == null
        ? null
        : {
            'tracking_number': 'JX123',
            'courier': 'jne',
            'status': shipmentStatus,
            'shipped_at': null,
            'delivered_at': null,
            'shipment_deadline': shipmentDeadline,
            'biteship_order_id': biteshipOrderId,
            'biteship_book_error': biteshipBookError,
            'origin_collection_method': originCollectionMethod,
            'status_history': statusHistory,
          },
  };
}

OrderModel _order(Map<String, dynamic> row) =>
    OrderModel.fromRow(row, storeName: 'buyer');

void main() {
  group('latestBiteshipStatus', () {
    test('picks the most recent entry by timestamp', () {
      final latest = latestBiteshipStatus([
        ShipmentStatusEntry(status: 'picked', at: DateTime(2026, 8, 20)),
        ShipmentStatusEntry(status: 'in_transit', at: DateTime(2026, 8, 22)),
        ShipmentStatusEntry(status: 'confirmed', at: DateTime(2026, 8, 19)),
      ]);
      expect(latest, 'in_transit');
    });

    test('breaks a timestamp tie on pipeline order', () {
      final at = DateTime(2026, 8, 22);
      final latest = latestBiteshipStatus([
        ShipmentStatusEntry(status: 'picked', at: at),
        ShipmentStatusEntry(status: 'delivered', at: at),
      ]);
      expect(latest, 'delivered');
    });

    test('normalises the casings Biteship has actually sent', () {
      expect(normalizeBiteshipStatus('inTransit'), 'in_transit');
      expect(normalizeBiteshipStatus('IN-TRANSIT'), 'in_transit');
      expect(normalizeBiteshipStatus('in transit'), 'in_transit');
    });

    test('an unrecognised status is dropped, not guessed at', () {
      expect(normalizeBiteshipStatus('teleported'), isNull);
      expect(
        latestBiteshipStatus([
          ShipmentStatusEntry(status: 'teleported', at: DateTime(2026, 8, 22)),
        ]),
        isNull,
      );
    });

    test('an entry with no timestamp is skipped', () {
      expect(
        latestBiteshipStatus([const ShipmentStatusEntry(status: 'picked')]),
        isNull,
      );
    });
  });

  group('bucketSellerOrder', () {
    test('a cancellation waiting on the seller outranks everything', () {
      final order = _order(
        _orderRow(cancelStatus: 'pending_seller', shipmentStatus: 'shipped'),
      );
      expect(bucketSellerOrder(order), SellerOrderTab.cancelRequested);
    });

    test('an open dispute outranks the shipment status', () {
      // The package being "received" is the very thing under dispute.
      final order = _order(
        _orderRow(disputeStatus: 'awaiting_seller', shipmentStatus: 'received'),
      );
      expect(bucketSellerOrder(order), SellerOrderTab.disputed);
    });

    test('a settled dispute does not strand the order in Komplain', () {
      final order = _order(
        _orderRow(disputeStatus: 'resolved', shipmentStatus: 'shipped'),
      );
      expect(bucketSellerOrder(order), SellerOrderTab.inTransit);
    });

    test('a returned package on a cancelled order counts as success', () {
      final order = _order(
        _orderRow(
          itemStatus: 'cancelled',
          statusHistory: [
            {'status': 'returned', 'at': '2026-08-22T09:00:00+00:00'},
          ],
        ),
      );
      expect(bucketSellerOrder(order), SellerOrderTab.success);
    });

    test('a returned package still flagged as an issue needs attention', () {
      final order = _order(
        _orderRow(
          shipmentStatus: 'issue',
          statusHistory: [
            {'status': 'returned', 'at': '2026-08-22T09:00:00+00:00'},
          ],
        ),
      );
      expect(bucketSellerOrder(order), SellerOrderTab.arrived);
    });

    test('an unpaid checkout buckets as awaiting payment', () {
      final order = _order(
        _orderRow(settlementStatus: 'awaiting_payment', paidAt: null),
      );
      expect(bucketSellerOrder(order), SellerOrderTab.awaitingPayment);
    });

    test('a booking that never took is failed', () {
      final order = _order(
        _orderRow(
          shipmentStatus: 'awaiting_shipment',
          biteshipBookError: 'courier_not_found',
          originCollectionMethod: 'pickup',
        ),
      );
      expect(bucketSellerOrder(order), SellerOrderTab.failed);
    });

    test('a book error the seller caused is not failed', () {
      // `seller_cancel*` is the seller's own doing, so the row stays in
      // whatever bucket its shipment says.
      final order = _order(
        _orderRow(
          shipmentStatus: 'awaiting_shipment',
          biteshipBookError: 'seller_cancelled_pickup',
        ),
      );
      expect(bucketSellerOrder(order), SellerOrderTab.urgent);
    });

    test('a book error that was retried successfully is not failed', () {
      final order = _order(
        _orderRow(
          shipmentStatus: 'awaiting_pickup',
          biteshipBookError: 'courier_not_found',
          biteshipOrderId: 'bit-1',
        ),
      );
      expect(bucketSellerOrder(order), SellerOrderTab.urgent);
    });

    test('shipment statuses map to their tabs', () {
      expect(
        bucketSellerOrder(_order(_orderRow(shipmentStatus: 'shipped'))),
        SellerOrderTab.inTransit,
      );
      expect(
        bucketSellerOrder(_order(_orderRow(shipmentStatus: 'received'))),
        SellerOrderTab.arrived,
      );
      expect(
        bucketSellerOrder(
          _order(_orderRow(shipmentStatus: 'awaiting_shipment')),
        ),
        SellerOrderTab.urgent,
      );
      expect(
        bucketSellerOrder(_order(_orderRow(shipmentStatus: 'awaiting_pickup'))),
        SellerOrderTab.urgent,
      );
    });

    test('completed and cancelled items reach their terminal tabs', () {
      expect(
        bucketSellerOrder(_order(_orderRow(itemStatus: 'completed'))),
        SellerOrderTab.success,
      );
      for (final status in ['cancelled', 'expired', 'rejected', 'refunded']) {
        expect(
          bucketSellerOrder(_order(_orderRow(itemStatus: status))),
          SellerOrderTab.failed,
          reason: status,
        );
      }
    });

    test('an order with no shipment yet belongs to no tab', () {
      expect(bucketSellerOrder(_order(_orderRow())), isNull);
    });
  });

  group('tabMatchesSellerOrder', () {
    test('Semua covers every bucket except unpaid checkouts', () {
      for (final bucket in SellerOrderTab.values) {
        expect(
          tabMatchesSellerOrder(SellerOrderTab.all, bucket),
          bucket != SellerOrderTab.awaitingPayment,
          reason: bucket.name,
        );
      }
      // Including rows that bucket to nothing at all.
      expect(tabMatchesSellerOrder(SellerOrderTab.all, null), isTrue);
    });

    test('every other tab takes only its own bucket', () {
      expect(
        tabMatchesSellerOrder(SellerOrderTab.urgent, SellerOrderTab.urgent),
        isTrue,
      );
      expect(
        tabMatchesSellerOrder(SellerOrderTab.urgent, SellerOrderTab.inTransit),
        isFalse,
      );
      expect(tabMatchesSellerOrder(SellerOrderTab.urgent, null), isFalse);
    });
  });

  group('SellerOrderSort', () {
    final older = _order(
      _orderRow(slug: 'a', createdAt: '2026-08-01T09:00:00+00:00', price: 50000),
    );
    final newer = _order(
      _orderRow(
        slug: 'b',
        createdAt: '2026-08-20T09:00:00+00:00',
        price: 300000,
      ),
    );

    test('newest first is the default order', () {
      expect(
        SellerOrderSort.newest.apply([older, newer]).map((o) => o.slug),
        ['b', 'a'],
      );
    });

    test('oldest reverses it', () {
      expect(
        SellerOrderSort.oldest.apply([newer, older]).map((o) => o.slug),
        ['a', 'b'],
      );
    });

    test('price sorts on the order total, shipping included', () {
      expect(
        SellerOrderSort.priceDesc.apply([older, newer]).map((o) => o.slug),
        ['b', 'a'],
      );
    });

    test('orders with no deadline sort last, not first', () {
      final withDeadline = _order(
        _orderRow(
          slug: 'deadline',
          shipmentStatus: 'awaiting_shipment',
          shipmentDeadline: '2026-08-25T09:00:00+00:00',
        ),
      );
      final without = _order(_orderRow(slug: 'none'));
      expect(
        SellerOrderSort.deadline
            .apply([without, withDeadline])
            .map((o) => o.slug),
        ['deadline', 'none'],
      );
    });
  });

  group('OrderModel seller fields', () {
    test('reads the shipment columns the buckets test', () {
      final order = _order(
        _orderRow(
          shipmentStatus: 'awaiting_pickup',
          shipmentDeadline: '2026-08-25T09:00:00+00:00',
          biteshipOrderId: 'bit-1',
          originCollectionMethod: 'pickup',
          statusHistory: [
            {'status': 'confirmed', 'at': '2026-08-21T09:00:00+00:00'},
          ],
        ),
      );
      expect(order.shipmentStatus, 'awaiting_pickup');
      expect(order.shipmentDeadline, isNotNull);
      expect(order.biteshipOrderId, 'bit-1');
      expect(order.originCollectionMethod, 'pickup');
      expect(order.statusHistory, hasLength(1));
    });

    test('an order with no shipment row reads as empty, not as a crash', () {
      final order = _order(_orderRow());
      expect(order.shipmentStatus, isNull);
      expect(order.statusHistory, isNull);
      expect(order.trackingNumber, isNull);
    });

    test('total counts quantity and shipping', () {
      final order = _order(
        _orderRow(price: 100000, quantity: 2, shippingCost: 20000),
      );
      expect(order.total, 220000);
      expect(order.totalQuantity, 2);
    });
  });

  group('PendingCheckout', () {
    List<Map<String, dynamic>> rows({int lines = 2}) => [
      for (var i = 0; i < lines; i++)
        {
          'cart_id': 42,
          'external_id': 'cart-ext-42',
          'buyer_username': 'ash',
          'created_at': '2026-08-20T09:00:00+00:00',
          'expires_at': '2099-08-20T10:00:00+00:00',
          'has_invoice': true,
          'card_id': 7 + i,
          'card_name': 'Charizard ex',
          'card_image_url': null,
          'expansion_code': 'SV2a',
          'collector_number': '201/165',
          'condition': 'NM',
          'price': 100000,
          'quantity': 1,
          'shipping_cost': 20000,
          'courier_service': 'reg',
        },
    ];

    test('folds the RPC rows of one cart into a single checkout', () {
      final checkout = PendingCheckout.fromRows(rows());
      expect(checkout.cartId, 42);
      expect(checkout.items, hasLength(2));
      expect(checkout.buyerUsername, 'ash');
      // Two lines at 100k + 20k shipping each.
      expect(checkout.total, 240000);
      expect(checkout.totalQuantity, 2);
    });

    test('labels itself the way web does', () {
      expect(PendingCheckout.fromRows(rows()).reference, 'CART-42');
    });

    test('an expired cart reports no time left rather than negative', () {
      final expired = rows(lines: 1);
      expired.first['expires_at'] = '2020-01-01T00:00:00+00:00';
      expect(PendingCheckout.fromRows(expired).remaining, Duration.zero);
    });
  });
}
