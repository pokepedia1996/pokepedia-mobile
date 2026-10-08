import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_pricing.dart';
import 'package:pokepedia_mobile/features/cart/repository/coupon_rules.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';

const _freeShipping = AppliedCoupon(
  couponId: 11,
  type: CouponType.freeShipping,
  slot: CouponSlot.shipping,
  value: 15000,
  minPurchase: 0,
);

const _feeWaiver = AppliedCoupon(
  couponId: 22,
  type: CouponType.waiveGatewayFee,
  slot: CouponSlot.fee,
  value: null,
  minPurchase: 0,
);

AvailableCoupon _row(
  AppliedCoupon coupon, {
  bool eligible = true,
  CouponIneligibleReason? reason,
}) => AvailableCoupon(
  couponId: coupon.couponId,
  code: 'C${coupon.couponId}',
  type: coupon.type,
  slot: coupon.slot,
  value: coupon.value,
  minPurchase: coupon.minPurchase,
  validUntil: null,
  discountAmount: 0,
  eligible: eligible,
  reason: reason,
  remainingUses: 1,
);

/// Pins the port of `computeCheckoutTotals` (web
/// `features/checkout/utils/pricing.ts`) against the same arithmetic the
/// lock RPCs run — a mismatch makes `commit_cart_match` reject the payment.
void main() {
  group('computeCheckoutTotals', () {
    test('no coupon charges the flat gateway fee on a channel', () {
      final totals = computeCheckoutTotals(
        itemsSubtotal: 100000,
        shippingTotal: 20000,
        insuranceTotal: 0,
        paymentMethod: PaymentMethod.xendit,
        paymentChannel: PaymentChannel.qris,
      );
      expect(totals.grandTotalBeforeFee, 120000);
      expect(totals.gatewayFeeCharged, platformBuyerFeeFlatIdr);
      expect(totals.shippingDiscount, 0);
      expect(totals.totalDiscount, 0);
      expect(totals.grandTotal, 122000);
      expect(totals.walletAmountDue, 120000);
    });

    test('free shipping is capped by its own value', () {
      final totals = computeCheckoutTotals(
        itemsSubtotal: 100000,
        shippingTotal: 20000,
        insuranceTotal: 0,
        paymentMethod: PaymentMethod.xendit,
        paymentChannel: PaymentChannel.qris,
        coupons: const CouponSelection(shipping: _freeShipping),
      );
      expect(totals.shippingDiscount, 15000);
      expect(totals.grandTotal, 120000 + 2000 - 15000);
      expect(totals.totalDiscount, 15000);
    });

    test('free shipping never discounts more than the shipping', () {
      final totals = computeCheckoutTotals(
        itemsSubtotal: 100000,
        shippingTotal: 9000,
        insuranceTotal: 0,
        paymentMethod: PaymentMethod.xendit,
        paymentChannel: PaymentChannel.qris,
        coupons: const CouponSelection(shipping: _freeShipping),
      );
      expect(totals.shippingDiscount, 9000);
      expect(totals.grandTotal, 100000 + 2000);
    });

    test('the fee waiver zeroes the charged fee and counts as a saving', () {
      final totals = computeCheckoutTotals(
        itemsSubtotal: 100000,
        shippingTotal: 20000,
        insuranceTotal: 5000,
        paymentMethod: PaymentMethod.xendit,
        paymentChannel: PaymentChannel.qris,
        coupons: const CouponSelection(fee: _feeWaiver),
      );
      expect(totals.gatewayFee, platformBuyerFeeFlatIdr);
      expect(totals.gatewayFeeWaived, isTrue);
      expect(totals.gatewayFeeCharged, 0);
      expect(totals.grandTotal, 125000);
      expect(totals.totalDiscount, platformBuyerFeeFlatIdr);
    });

    test('the fee waiver waives nothing before a channel is picked', () {
      final totals = computeCheckoutTotals(
        itemsSubtotal: 100000,
        shippingTotal: 20000,
        insuranceTotal: 0,
        paymentMethod: PaymentMethod.xendit,
        paymentChannel: null,
        coupons: const CouponSelection(fee: _feeWaiver),
      );
      expect(totals.gatewayFeeWaived, isFalse);
      expect(totals.totalDiscount, 0);
    });

    test('both coupons stack across their two slots', () {
      final totals = computeCheckoutTotals(
        itemsSubtotal: 100000,
        shippingTotal: 20000,
        insuranceTotal: 0,
        paymentMethod: PaymentMethod.xendit,
        paymentChannel: PaymentChannel.bni,
        coupons: const CouponSelection(
          shipping: _freeShipping,
          fee: _feeWaiver,
        ),
      );
      expect(totals.grandTotal, 120000 - 15000);
      expect(totals.totalDiscount, 15000 + platformBuyerFeeFlatIdr);
      expect(
        const CouponSelection(shipping: _freeShipping, fee: _feeWaiver).ids,
        [11, 22],
      );
    });

    test('saldo owes the total less the shipping discount, with no fee', () {
      final totals = computeCheckoutTotals(
        itemsSubtotal: 100000,
        shippingTotal: 20000,
        insuranceTotal: 3000,
        paymentMethod: PaymentMethod.wallet,
        paymentChannel: null,
        coupons: const CouponSelection(
          shipping: _freeShipping,
          fee: _feeWaiver,
        ),
      );
      expect(totals.gatewayFeeCharged, 0);
      expect(totals.gatewayFeeWaived, isFalse);
      expect(totals.walletAmountDue, 123000 - 15000);
      expect(totals.grandTotal, totals.walletAmountDue);
    });

    test('a total is never negative', () {
      final totals = computeCheckoutTotals(
        itemsSubtotal: 0,
        shippingTotal: 10000,
        insuranceTotal: 0,
        paymentMethod: PaymentMethod.wallet,
        paymentChannel: null,
        coupons: const CouponSelection(shipping: _freeShipping),
      );
      expect(totals.grandTotal, 0);
      expect(totals.walletAmountDue, 0);
    });
  });

  group('autoSelectPayment against walletAmountDue', () {
    test('saldo is picked when it covers the discounted amount', () {
      final pick = autoSelectPayment(
        grandTotalIdr: 120000,
        walletBalance: 110000,
        walletAmountDue: 105000,
      );
      expect(pick.method, PaymentMethod.wallet);
    });

    test('without a discount the full total still decides', () {
      final pick = autoSelectPayment(
        grandTotalIdr: 120000,
        walletBalance: 110000,
      );
      expect(pick.method, PaymentMethod.xendit);
    });
  });

  group('resolveCouponSelection', () {
    CouponSelection resolve({
      required List<AvailableCoupon> catalog,
      CouponOverrides overrides = const CouponOverrides(subtotal: 100000),
      PaymentMethod method = PaymentMethod.xendit,
      PaymentChannel? channel = PaymentChannel.qris,
      int shippingTotal = 20000,
      int itemsSubtotal = 100000,
    }) => resolveCouponSelection(
      catalog: catalog,
      overrides: overrides,
      itemsSubtotal: itemsSubtotal,
      paymentMethod: method,
      paymentChannel: channel,
      shippingTotal: shippingTotal,
    );

    test('applies the best eligible coupon per slot by default', () {
      final selection = resolve(
        catalog: [_row(_freeShipping), _row(_feeWaiver)],
      );
      expect(selection.shipping?.couponId, 11);
      expect(selection.fee?.couponId, 22);
    });

    test('skips ineligible rows', () {
      final selection = resolve(
        catalog: [
          _row(
            _freeShipping,
            eligible: false,
            reason: CouponIneligibleReason.minPurchase,
          ),
        ],
      );
      expect(selection.shipping, isNull);
    });

    test('drops the fee waiver on saldo but keeps free shipping', () {
      final selection = resolve(
        catalog: [_row(_freeShipping), _row(_feeWaiver)],
        method: PaymentMethod.wallet,
        channel: null,
      );
      expect(selection.shipping?.couponId, 11);
      expect(selection.fee, isNull);
    });

    test('a declined slot stays empty until the cart changes', () {
      final declined = const CouponOverrides(
        subtotal: 100000,
      ).withSlot(CouponSlot.shipping, null, itemsSubtotal: 100000);
      final catalog = [_row(_freeShipping)];
      expect(resolve(catalog: catalog, overrides: declined).shipping, isNull);
      expect(
        resolve(
          catalog: catalog,
          overrides: declined,
          itemsSubtotal: 150000,
        ).shipping?.couponId,
        11,
      );
    });

    test('a chosen coupon missing from the catalog is dropped', () {
      final chosen = const CouponOverrides(
        subtotal: 100000,
      ).withSlot(CouponSlot.fee, _feeWaiver, itemsSubtotal: 100000);
      expect(
        resolve(catalog: [_row(_freeShipping)], overrides: chosen).fee,
        isNull,
      );
    });
  });

  group('AvailableCoupon.tryParse', () {
    test('reads a list_available_coupons row', () {
      final coupon = AvailableCoupon.tryParse({
        'coupon_id': 7,
        'code': 'ONGKIR',
        'type': 'free_shipping',
        'slot': 'shipping',
        'value': 10000,
        'min_purchase': 50000,
        'valid_until': '2026-12-31T16:59:59Z',
        'discount_amount': 10000,
        'eligible': false,
        'reason': 'min_purchase',
        'remaining_uses': 1,
        'remaining_global': null,
      });
      expect(coupon?.type, CouponType.freeShipping);
      expect(coupon?.slot, CouponSlot.shipping);
      expect(coupon?.reason, CouponIneligibleReason.minPurchase);
      expect(coupon?.eligible, isFalse);
    });

    test('drops a type this build does not know', () {
      expect(
        AvailableCoupon.tryParse({
          'coupon_id': 8,
          'type': 'percent_off',
          'slot': 'items',
        }),
        isNull,
      );
    });
  });
}
