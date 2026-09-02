import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/seller_order.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/seller_order_detail.dart';

Map<String, dynamic> _orderRow({
  String? collectionMethod,
  String? courierCompany,
  String? shipmentSlug = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
}) => {
  'id': 1,
  'slug': 'order-1',
  'order_number': 'ORD-1',
  'status': 'awaiting_shipment',
  'created_at': '2026-09-01T00:00:00Z',
  'seller_id': 'seller',
  'buyer_id': 'buyer',
  'order_items': [
    {
      'id': 1,
      'slug': 'item-1',
      'order_number': 'ORD-1',
      'card_id': 1,
      'matched_quantity': 1,
      'match_price': 50000,
      'status': 'matched',
      'created_at': '2026-09-01T00:00:00Z',
      'settlements': {
        'condition': 'NM',
        'escrow_amount': 50000,
        'shipping_cost': 20000,
        'status': 'in_escrow',
        'paid_at': '2026-09-01T01:00:00Z',
        'available_collection_method': collectionMethod,
        'courier_company': courierCompany,
      },
    },
  ],
  'shipments': {
    if (shipmentSlug != null) 'slug': shipmentSlug,
    'status': 'awaiting_shipment',
  },
};

SellerOrderDetail _detail(Map<String, dynamic> row) =>
    SellerOrderDetail.fromRow(
      row,
      order: OrderModel.fromRow(row, storeName: 'Pembeli'),
    );

/// The dispatch sheet decides what a seller may do from these, and the
/// dashboard's counters link by filter key. Both are silent when wrong: a bad
/// key opens the wrong tab, a bad method offers a dispatch the server refuses.
void main() {
  group('SellerOrderTab.filterKey', () {
    test('matches web SELLER_ORDER_TABS keys', () {
      expect(SellerOrderTab.urgent.filterKey, 'urgent');
      expect(SellerOrderTab.inTransit.filterKey, 'in_transit');
      expect(SellerOrderTab.disputed.filterKey, 'disputed');
      expect(SellerOrderTab.awaitingPayment.filterKey, 'awaiting_payment');
      expect(SellerOrderTab.cancelRequested.filterKey, 'cancel_requested');
    });

    test('round-trips every tab through fromFilterKey', () {
      for (final tab in SellerOrderTab.values) {
        expect(SellerOrderTab.fromFilterKey(tab.filterKey), tab);
      }
    });

    test('ignores a key it does not know', () {
      expect(SellerOrderTab.fromFilterKey('nonsense'), isNull);
      expect(SellerOrderTab.fromFilterKey(null), isNull);
    });
  });

  group('dispatch options', () {
    test('offers both when the courier never said what it takes', () {
      final detail = _detail(_orderRow());
      expect(detail.availableCollectionMethods, isNull);
      expect(detail.allowsPickup, isTrue);
      expect(detail.allowsManualResi, isTrue);
    });

    test('drops pickup when the courier only accepts drop-off', () {
      final detail = _detail(_orderRow(collectionMethod: 'drop_off'));
      expect(detail.allowsPickup, isFalse);
      expect(detail.allowsManualResi, isTrue);
    });

    test('reads a comma-joined list of methods', () {
      final detail = _detail(_orderRow(collectionMethod: 'pickup, drop_off'));
      expect(detail.availableCollectionMethods, ['pickup', 'drop_off']);
      expect(detail.allowsPickup, isTrue);
    });

    test('an instant courier can only be picked up', () {
      final detail = _detail(_orderRow(courierCompany: 'gojek'));
      expect(detail.isInstantCourier, isTrue);
      expect(detail.allowsManualResi, isFalse);
      expect(detail.allowsPickup, isTrue);
    });

    test('carries the shipment slug the dispatch route needs', () {
      expect(
        _detail(_orderRow()).order.shipmentSlug,
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
      );
      expect(_detail(_orderRow(shipmentSlug: null)).order.shipmentSlug, isNull);
    });
  });
}
