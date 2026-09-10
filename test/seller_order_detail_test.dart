import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/seller_order_detail.dart';

Map<String, dynamic> _card(int id) => {
  'id': id,
  'name_id': 'Charizard ex',
  'expansion_code': 'SV2a',
  'collector_number': '201/165',
  'rarity': 'SAR',
  'category': 'pokemon',
  'image_url': null,
  'illustrator': null,
  'regulation_mark': null,
  'language': 'id',
  'variant': 'normal',
  'details': <String, dynamic>{},
};

Map<String, dynamic> _item({
  int id = 1,
  int price = 100000,
  int quantity = 1,
  int shipping = 20000,
  int insurance = 0,
  int commission = 5000,
  int net = 115000,
  String? settlementStatus = 'in_escrow',
  String? paidAt = '2026-08-02T00:00:00Z',
  List<Map<String, dynamic>> disputes = const [],
}) => {
  'id': id,
  'slug': 'item-$id',
  'order_number': 'ORD-$id',
  'card_id': id,
  'matched_quantity': quantity,
  'match_price': price,
  'status': 'paid',
  'created_at': '2026-08-01T00:00:00Z',
  'cards': _card(id),
  'settlements': {
    'condition': 'NM',
    'escrow_amount': price * quantity,
    'shipping_cost': shipping,
    'status': settlementStatus,
    'paid_at': paidAt,
    'payment_deadline': null,
    'cancel_status': null,
    'cancel_reason': null,
    'commission_amount': commission,
    'seller_net_amount': net,
    'insurance_premium_idr': insurance,
  },
  'disputes': disputes,
};

Map<String, dynamic> _row({
  List<Map<String, dynamic>>? items,
  Map<String, dynamic>? shipment,
}) => {
  'id': 1,
  'slug': 'order-1',
  'order_number': 'ORD-1',
  'status': 'paid',
  'created_at': '2026-08-01T00:00:00Z',
  'seller_id': 'seller-1',
  'buyer_id': 'buyer-1',
  'order_items': items ?? [_item()],
  'shipments': shipment,
};

SellerOrderDetail _detail(Map<String, dynamic> row, {String? buyer}) =>
    SellerOrderDetail.fromRow(
      row,
      order: OrderModel.fromRow(row, storeName: buyer ?? 'Pembeli'),
      buyerUsername: buyer,
    );

void main() {
  group('money', () {
    test('sums the settlement across every item in the order', () {
      // Web aggregates sibling matches from the same checkout; an `orders`
      // row is already that grouping, so the sum is over its own items.
      final detail = _detail(
        _row(
          items: [
            _item(
              id: 1,
              price: 100000,
              shipping: 20000,
              commission: 5000,
              net: 115000,
            ),
            _item(
              id: 2,
              price: 50000,
              shipping: 0,
              commission: 2500,
              net: 47500,
            ),
          ],
        ),
      );

      expect(detail.subtotal, 150000);
      expect(detail.shippingCost, 20000);
      expect(detail.commissionAmount, 7500);
      expect(detail.sellerNetAmount, 162500);
    });

    test('quantity multiplies into the subtotal', () {
      final detail = _detail(_row(items: [_item(price: 100000, quantity: 3)]));
      expect(detail.subtotal, 300000);
    });

    test('buyerPaid excludes the fees only the buyer can read', () {
      // `carts_select_own` reserves gateway_fee and discount_amount for the
      // buyer, so this is what the buyer paid *this seller*, not the
      // checkout total. Web's page shows the same figure for the same
      // reason.
      final detail = _detail(
        _row(items: [_item(price: 100000, shipping: 20000, insurance: 3000)]),
      );
      expect(detail.insuranceFee, 3000);
      expect(detail.buyerPaid, 123000);
    });

    test('a missing settlement contributes nothing rather than crashing', () {
      final row = _row(items: [_item()..['settlements'] = null]);
      final detail = _detail(row);

      expect(detail.subtotal, 100000);
      expect(detail.sellerNetAmount, 0);
      expect(detail.commissionAmount, 0);
    });
  });

  group('state', () {
    test('escrow is money still held', () {
      expect(_detail(_row()).inEscrow, isTrue);
      expect(
        _detail(_row(items: [_item(settlementStatus: 'released')])).inEscrow,
        isFalse,
      );
    });

    test('a settled dispute is history, not an open one', () {
      // `resolved` is outside `activeDisputeStatuses`, so the payout note
      // must not keep claiming the money is held for a complaint.
      final detail = _detail(
        _row(
          items: [
            _item(
              disputes: [
                {'slug': 'd-1', 'current_status': 'resolved'},
              ],
            ),
          ],
        ),
      );
      expect(detail.hasOpenDispute, isFalse);
      expect(detail.inEscrow, isTrue);
    });

    test('a disputed item is not counted as ordinary escrow', () {
      // Its money is held for a different reason, and the payout note has
      // to say which — "waiting on the buyer" is wrong during a complaint.
      final detail = _detail(
        _row(
          items: [
            _item(
              disputes: [
                {'slug': 'd-1', 'current_status': 'awaiting_seller'},
              ],
            ),
          ],
        ),
      );

      expect(detail.hasOpenDispute, isTrue);
      expect(detail.disputedCount, 1);
      expect(detail.inEscrow, isFalse);
    });

    test('unpaid until a settlement records payment', () {
      expect(
        _detail(_row(items: [_item(paidAt: null)])).awaitingPayment,
        isTrue,
      );
      expect(_detail(_row()).awaitingPayment, isFalse);
    });
  });

  group('destination', () {
    test('reads the shipment address', () {
      final detail = _detail(
        _row(
          shipment: {
            'tracking_number': 'JX123',
            'courier': 'jne',
            'status': 'picked',
            'destination_contact_name': 'Ash',
            'destination_contact_phone': '0812',
            'destination_full_address': 'Jl. Pallet 1',
            'destination_district': 'Menteng',
            'destination_city': 'Jakarta Pusat',
            'destination_province': 'DKI Jakarta',
            'destination_postal_code': '10310',
          },
        ),
      );

      expect(detail.destination!.contactName, 'Ash');
      expect(
        detail.destination!.areaLine,
        'Menteng, Jakarta Pusat, DKI Jakarta, 10310',
      );
    });

    test('no shipment means no address to show', () {
      // Before a shipment exists the buyer's address is still theirs alone.
      expect(_detail(_row()).destination, isNull);
    });

    test('a shipment carrying no address at all is treated as none', () {
      // Rather than rendering an empty "Alamat tujuan" card.
      final detail = _detail(
        _row(
          shipment: {'tracking_number': null, 'status': 'awaiting_shipment'},
        ),
      );
      expect(detail.destination, isNull);
    });

    test('a partial address still prints what it has', () {
      final detail = _detail(
        _row(
          shipment: {
            'status': 'awaiting_shipment',
            'destination_city': 'Bandung',
          },
        ),
      );
      expect(detail.destination!.areaLine, 'Bandung');
    });
  });
}
