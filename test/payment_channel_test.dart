import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/cart/repository/checkout_pricing.dart';
import 'package:pokepedia_mobile/features/cart/repository/models/checkout_models.dart';

void main() {
  group('availablePaymentChannels', () {
    test('QRIS below the cap, VA banks at or above it', () {
      expect(availablePaymentChannels(599999), [PaymentChannel.qris]);
      expect(
        availablePaymentChannels(600000),
        isNot(contains(PaymentChannel.qris)),
      );
      expect(availablePaymentChannels(600000), [
        PaymentChannel.bni,
        PaymentChannel.bri,
        PaymentChannel.mandiri,
        PaymentChannel.permata,
        PaymentChannel.cimb,
      ]);
    });

    test('the cap is exclusive, matching web\'s `<` comparison', () {
      // Exactly Rp600.000 is a VA cart, not a QRIS one. Off by one here and
      // the app offers a channel the server will refuse.
      expect(isChannelAllowedForAmount(PaymentChannel.qris, 599999), isTrue);
      expect(isChannelAllowedForAmount(PaymentChannel.qris, 600000), isFalse);
      expect(isChannelAllowedForAmount(PaymentChannel.bni, 599999), isFalse);
      expect(isChannelAllowedForAmount(PaymentChannel.bni, 600000), isTrue);
    });

    test('every total has at least one channel to offer', () {
      // The auto-select rule depends on this: an empty list would leave the
      // buyer with no channel and a permanently disabled pay button.
      for (final total in [1, 100000, 599999, 600000, 5000000]) {
        expect(
          availablePaymentChannels(total),
          isNotEmpty,
          reason: 'total $total',
        );
      }
    });
  });

  group('insurance threshold', () {
    test('mandatory strictly above Rp500.000', () {
      expect(isInsuranceMandatory(500000), isFalse);
      expect(isInsuranceMandatory(500001), isTrue);
    });

    test('crossing it can push a QRIS cart over the QRIS cap', () {
      // The sequence the picker had no answer for: a Rp560.000 cart is QRIS
      // eligible, mandatory insurance lands on top, and the total crosses
      // Rp600.000 while QRIS is still selected.
      const sellerSubtotal = 560000;
      expect(isInsuranceMandatory(sellerSubtotal), isTrue);
      expect(
        isChannelAllowedForAmount(PaymentChannel.qris, sellerSubtotal),
        isTrue,
      );
      expect(
        isChannelAllowedForAmount(PaymentChannel.qris, sellerSubtotal + 50000),
        isFalse,
      );
    });
  });

  group('autoSelectPayment', () {
    // The buyer is never asked to pick first; these are the defaults they
    // land on, in the order the rule resolves them.

    test('saldo wins whenever it covers the bill', () {
      final pick = autoSelectPayment(
        grandTotalIdr: 250000,
        walletBalance: 300000,
      );
      expect(pick.method, PaymentMethod.wallet);
      expect(pick.channel, isNull);
    });

    test('exactly enough saldo still counts', () {
      final pick = autoSelectPayment(
        grandTotalIdr: 250000,
        walletBalance: 250000,
      );
      expect(pick.method, PaymentMethod.wallet);
    });

    test('a short balance falls to QRIS under the cap', () {
      final pick = autoSelectPayment(
        grandTotalIdr: 250000,
        walletBalance: 249999,
      );
      expect(pick.method, PaymentMethod.xendit);
      expect(pick.channel, PaymentChannel.qris);
    });

    test('an empty wallet on a big bill lands on a VA bank', () {
      final pick = autoSelectPayment(grandTotalIdr: 750000, walletBalance: 0);
      expect(pick.method, PaymentMethod.xendit);
      expect(pick.channel, PaymentChannel.bni);
    });

    test('the bank last paid with is preferred over the first in the list', () {
      final pick = autoSelectPayment(
        grandTotalIdr: 750000,
        walletBalance: 0,
        lastPaidChannel: PaymentChannel.mandiri,
      );
      expect(pick.channel, PaymentChannel.mandiri);
    });

    test('a VA habit gives way to QRIS below the cap', () {
      // The case the request names outright: last time was a VA bank, but
      // this bill is small, so VA is not on offer at all.
      final pick = autoSelectPayment(
        grandTotalIdr: 599999,
        walletBalance: 0,
        lastPaidChannel: PaymentChannel.bni,
      );
      expect(pick.channel, PaymentChannel.qris);
    });

    test('a QRIS habit gives way to VA at the cap', () {
      final pick = autoSelectPayment(
        grandTotalIdr: 600000,
        walletBalance: 0,
        lastPaidChannel: PaymentChannel.qris,
      );
      expect(pick.channel, PaymentChannel.bni);
    });

    test('saldo outranks a VA habit', () {
      final pick = autoSelectPayment(
        grandTotalIdr: 700000,
        walletBalance: 700000,
        lastPaidChannel: PaymentChannel.bri,
      );
      expect(pick.method, PaymentMethod.wallet);
    });

    test('a fee-waiver coupon keeps the buyer on the gateway', () {
      // Saldo pays no gateway fee, so switching would void the coupon the
      // buyer just applied.
      final pick = autoSelectPayment(
        grandTotalIdr: 700000,
        walletBalance: 700000,
        lastPaidChannel: PaymentChannel.bri,
        holdsFeeWaiver: true,
      );
      expect(pick.method, PaymentMethod.xendit);
      expect(pick.channel, PaymentChannel.bri);
    });
  });
}
