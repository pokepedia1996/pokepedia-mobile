import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/utils/postgrest_embed.dart';

/// PostgREST sends a one-to-one embed as an object and a one-to-many as an
/// array, decided by whether the foreign key is unique. The orders page
/// broke on exactly that: `settlements.order_item_id` is unique, so it
/// arrives as an object, and a `List` cast threw.
void main() {
  group('embeddedRow', () {
    test('reads the object shape', () {
      expect(embeddedRow({'condition': 'NM'}), {'condition': 'NM'});
    });

    test('reads the array shape', () {
      expect(embeddedRow([
        {'condition': 'LP'},
      ]), {'condition': 'LP'});
    });

    test('an absent or empty embed is null, not a crash', () {
      expect(embeddedRow(null), isNull);
      expect(embeddedRow(const []), isNull);
    });
  });

  group('embeddedRows', () {
    test('takes either shape', () {
      expect(embeddedRows([
        {'a': 1},
        {'a': 2},
      ]), hasLength(2));
      expect(embeddedRows({'a': 1}), hasLength(1));
      expect(embeddedRows(null), isEmpty);
    });
  });

  test('an order parses with settlements as an object', () {
    // The shape production actually returns, which is what threw before.
    final order = OrderModel.fromRow({
      'slug': 'ord-1',
      'order_number': 'PKP-1',
      'status': 'shipped',
      'created_at': '2026-08-01T00:00:00Z',
      'order_items': [
        {
          'slug': 'oi-1',
          'order_number': 'PKP-1',
          'card_id': 1,
          'matched_quantity': 2,
          'match_price': 25000,
          'status': 'in_escrow',
          'created_at': '2026-08-01T00:00:00Z',
          'cards': {
            'id': 1,
            'name_id': 'Charmander',
            'expansion_code': 'DF',
            'collector_number': '079/101',
            'category': 'pokemon',
          },
          'settlements': {
            'condition': 'LP',
            'shipping_cost': 18000,
            'status': 'shipped',
            'paid_at': '2026-08-01T01:00:00Z',
          },
        },
      ],
      'shipments': [
        {'tracking_number': 'JX1ID', 'courier': 'JNE'},
      ],
    }, storeName: 'Toko Ash');

    expect(order.items, hasLength(1));
    expect(order.items.first.condition.short, 'LP');
    expect(order.items.first.shippingCost, 18000);
    expect(order.trackingNumber, 'JX1ID');
    // Paid, so it belongs under "Dikirim" rather than "Belum Bayar".
    expect(order.isUnpaid, isFalse);
    expect(order.tab, OrderTab.shipped);
  });

  test('the same row parses from the seller side', () {
    // Only the counterparty differs: `storeName` carries whoever is on the
    // other side, the buyer's username when selling.
    final order = OrderModel.fromRow({
      'slug': 'ord-3',
      'order_number': 'PKP-3',
      'status': 'awaiting_shipment',
      'created_at': '2026-08-01T00:00:00Z',
      'order_items': [
        {
          'slug': 'oi-3',
          'card_id': 1,
          'match_price': 50000,
          'matched_quantity': 1,
          'status': 'accepted',
          'cards': {
            'id': 1,
            'name_id': 'Charmander',
            'expansion_code': 'DF',
            'collector_number': '079/101',
            'category': 'pokemon',
          },
          'settlements': {'status': 'awaiting_shipment', 'paid_at': '2026-08-01T01:00:00Z'},
        },
      ],
    }, storeName: 'ash_ketchum');

    expect(order.storeName, 'ash_ketchum');
    expect(order.isUnpaid, isFalse);
    expect(order.tab, OrderTab.processing);
  });

  test('an unpaid order lands in the Belum Bayar tab', () {
    final order = OrderModel.fromRow({
      'slug': 'ord-2',
      'order_number': 'PKP-2',
      'status': 'awaiting_shipment',
      'created_at': '2026-08-01T00:00:00Z',
      'order_items': [
        {
          'slug': 'oi-2',
          'card_id': 1,
          'match_price': 1000,
          'status': 'pending_acceptance',
          'cards': {
            'id': 1,
            'name_id': 'Pikachu',
            'expansion_code': 'DF',
            'collector_number': '001/101',
            'category': 'pokemon',
          },
          'settlements': {'status': 'awaiting_payment', 'paid_at': null},
        },
      ],
    }, storeName: 'Toko Ash');

    expect(order.isUnpaid, isTrue);
    expect(order.tab, OrderTab.unpaid);
  });
}
