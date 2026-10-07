import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/order_model.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/pending_checkout.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/seller_order.dart';
import 'package:pokepedia_mobile/features/orders/repository/models/seller_order_detail.dart';
import 'package:pokepedia_mobile/features/orders/utils/package_payment.dart';

PackagePaymentLine _line(
  int subtotal, [
  int shippingCost = 0,
  int shippingDiscount = 0,
  int insurance = 0,
  bool cancelled = false,
]) => PackagePaymentLine(
  subtotal: subtotal,
  shippingCost: shippingCost,
  shippingDiscount: shippingDiscount,
  insurance: insurance,
  cancelled: cancelled,
);

PackageCheckoutFees _fees(int total, int fee, int charged) =>
    PackageCheckoutFees(
      totalAmount: total,
      gatewayFee: fee,
      gatewayFeeCharged: charged,
    );

Map<String, dynamic> _item({
  int id = 11,
  String slug = 'item-1',
  int price = 25000,
  int qty = 1,
  String status = 'shipped',
  int shipping = 0,
  int discount = 0,
  int insurance = 0,
  Map<String, dynamic>? cart,
}) => {
  'id': id,
  'slug': slug,
  'order_number': 'ord-1',
  'card_id': 7,
  'matched_quantity': qty,
  'match_price': price,
  'status': status,
  'created_at': '2026-10-01T09:00:00+00:00',
  'cards': null,
  'settlements': {
    'slug': 'settlement-$id',
    'condition': 'NM',
    'escrow_amount': price * qty,
    'shipping_cost': shipping,
    'shipping_discount_idr': discount,
    'insurance_fee_idr': insurance,
    'status': 'shipped',
    'paid_at': '2026-10-01T09:00:00+00:00',
    'commission_amount': 750,
    'seller_net_amount': price * qty - 750,
    'carts': cart,
  },
  'disputes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _orderRow(
  List<Map<String, dynamic>> items, {
  Map<String, dynamic>? shipment,
}) => {
  'id': 1,
  'slug': 'order-1',
  'order_number': 'ord-1',
  'status': 'shipped',
  'created_at': '2026-10-01T09:00:00+00:00',
  'seller_id': 'seller',
  'buyer_id': 'buyer',
  'order_items': items,
  'shipments': shipment,
};

void main() {
  group('computePackagePayment', () {
    test('nets the ongkir coupon and a waived fee for a whole checkout', () {
      final result = computePackagePayment([
        _line(25000, 9000, 9000),
        _line(67500),
      ], _fees(101500, 2000, 0));
      expect(result.subtotal, 92500);
      expect(result.shippingGross, 9000);
      expect(result.shippingDiscount, 9000);
      expect(result.showCheckoutFee, isTrue);
      expect(result.platformFee, 2000);
      expect(result.platformFeeWaived, 2000);
      expect(result.isPlatformFeeWaived, isTrue);
      expect(result.paidTotal, 92500);
      expect(result.originalPaidTotal, 92500);
    });

    test('includes insurance and a charged fee', () {
      final result = computePackagePayment([
        _line(20000, 12000, 10000, 275),
        _line(35000),
      ], _fees(67275, 2000, 2000));
      expect(result.platformFeeWaived, 0);
      expect(result.paidTotal, 59275);
    });

    test('drops checkout fees for one package of a multi-seller cart', () {
      final result = computePackagePayment([
        _line(15000, 16000, 10000),
      ], _fees(46000, 2000, 2000));
      expect(result.showCheckoutFee, isFalse);
      expect(result.platformFee, 0);
      expect(result.paidTotal, 21000);
    });

    test('falls back to gross lines when the checkout is unknown', () {
      final result = computePackagePayment([_line(30000, 9000)], null);
      expect(result.showCheckoutFee, isFalse);
      expect(result.paidTotal, 39000);
    });

    test('never lets a discount exceed its line shipping', () {
      final result = computePackagePayment([_line(30000, 5000, 9000)], null);
      expect(result.shippingDiscount, 5000);
      expect(result.paidTotal, 30000);
    });

    test('drops a cancelled line but keeps the checkout fee row', () {
      final result = computePackagePayment([
        _line(25000, 9000),
        _line(40000, 0, 0, 0, true),
      ], _fees(74000, 2000, 2000));
      expect(result.showCheckoutFee, isTrue);
      expect(result.subtotal, 25000);
      expect(result.paidTotal, 36000);
      expect(result.cancelledCount, 1);
      expect(result.cancelledAmount, 40000);
      expect(result.originalPaidTotal, 76000);
    });

    test('leaves only the charged fee when the whole package is cancelled', () {
      final result = computePackagePayment([
        _line(25000, 9000, 9000, 275, true),
        _line(15000, 0, 0, 0, true),
      ], _fees(49275, 2000, 2000));
      expect(result.paidTotal, 2000);
      expect(result.cancelledAmount, 40275);
      expect(result.originalPaidTotal, 42275);
    });
  });

  group('OrderModel totals', () {
    test('Total dibayar nets coupon, adds insurance and the charged fee', () {
      final cart = {
        'total_amount': 67275,
        'gateway_fee': 2000,
        'gateway_fee_charged': 2000,
      };
      final order = OrderModel.fromRow(
        _orderRow([
          _item(
            price: 20000,
            shipping: 12000,
            discount: 10000,
            insurance: 275,
            cart: cart,
          ),
          _item(id: 12, slug: 'item-2', price: 35000, cart: cart),
        ]),
        storeName: 'Toko',
      );
      expect(order.payment.paidTotal, 59275);
      expect(order.payment.insurance, 275);
      expect(order.total, 59275);
    });

    test('a fully cancelled package lists what was originally paid', () {
      final order = OrderModel.fromRow(
        _orderRow([_item(status: 'cancelled', shipping: 9000)]),
        storeName: 'Toko',
      );
      expect(order.payment.paidTotal, 0);
      expect(order.total, 34000);
    });
  });

  test(
    'seller buyerPaid nets the ongkir coupon and reads insurance_fee_idr',
    () {
      final row = _orderRow([
        _item(price: 20000, shipping: 12000, discount: 10000, insurance: 275),
        _item(id: 12, slug: 'item-2', price: 5000, status: 'cancelled'),
      ]);
      final detail = SellerOrderDetail.fromRow(
        row,
        order: OrderModel.fromRow(row, storeName: 'Pembeli'),
      );
      expect(detail.subtotal, 20000);
      expect(detail.shippingDiscount, 10000);
      expect(detail.insuranceFee, 275);
      expect(detail.buyerPaid, 22275);
      expect(detail.commissionAmount, 750);
    },
  );

  group('untrackable couriers', () {
    test('the set matches web, sicepat included', () {
      expect(untrackableCourierCodes, {
        'jne',
        'idexpress',
        'pos',
        'tiki',
        'paxel',
        'sicepat',
      });
      expect(isUntrackableCourier(' SiCepat '), isTrue);
      expect(isUntrackableCourier('jnt'), isFalse);
      expect(isUntrackableCourier(null), isFalse);
    });

    Map<String, dynamic> shipment({String? courier, String? courierCode}) => {
      'courier': courier,
      'courier_code': courierCode,
      'origin_collection_method': 'manual',
      'status': 'shipped',
      'shipped_at': '2026-10-01T09:00:00+00:00',
    };

    test('keys on courier_code over the display courier', () {
      final order = OrderModel.fromRow(
        _orderRow(
          [_item()],
          shipment: shipment(
            courier: 'SiCepat Ekspres',
            courierCode: 'sicepat',
          ),
        ),
        storeName: 'Toko',
      );
      expect(order.isUntrackableManual, isTrue);
      expect(
        order.canConfirmReceiptAt(DateTime.parse('2026-10-02T10:00:00Z')),
        isTrue,
      );
    });

    test('a trackable courier_code wins over an untrackable-looking name', () {
      final order = OrderModel.fromRow(
        _orderRow([
          _item(),
        ], shipment: shipment(courier: 'jne', courierCode: 'jnt')),
        storeName: 'Toko',
      );
      expect(order.isUntrackableManual, isFalse);
    });

    test('falls back to courier when courier_code is null', () {
      final order = OrderModel.fromRow(
        _orderRow([_item()], shipment: shipment(courier: 'jne')),
        storeName: 'Toko',
      );
      expect(order.isUntrackableManual, isTrue);
    });
  });

  group('cartChargedAmount', () {
    test('prefers invoice_amount', () {
      expect(
        cartChargedAmount({'total_amount': 101500, 'invoice_amount': 92500}),
        92500,
      );
    });

    test('falls back to total_amount', () {
      expect(
        cartChargedAmount({'total_amount': 101500, 'invoice_amount': null}),
        101500,
      );
    });

    test('the buyer pending checkout bills the invoice amount', () {
      final checkout = pendingCheckoutFromCart({
        'id': 5,
        'external_id': 'cart-5',
        'total_amount': 101500,
        'invoice_amount': 94500,
        'created_at': '2026-10-01T09:00:00+00:00',
        'cart_snapshot': [
          {'price': 92500, 'quantity': 1, 'shipping_cost': 9000},
        ],
      });
      expect(checkout.total, 94500);
    });
  });
}
