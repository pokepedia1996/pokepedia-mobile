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
}
