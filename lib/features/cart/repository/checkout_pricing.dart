import 'models/checkout_models.dart';

/// Pricing constants and pure calculations for the checkout flow. Ports
/// `features/checkout/model/pricing.ts` and the relevant bits of
/// `lib/payments/pricing.ts`.
const insuranceMandatoryThresholdIdr = 500000;
const platformBuyerFeeFlatIdr = 2000;
const qrisMaxIdr = 600000;

bool isInsuranceMandatory(int sellerSubtotal) =>
    sellerSubtotal > insuranceMandatoryThresholdIdr;

/// Mirrors `getAvailablePaymentChannels`: QRIS below the threshold, VA banks
/// at or above it.
List<PaymentChannel> availablePaymentChannels(int grandTotalIdr) {
  if (grandTotalIdr < qrisMaxIdr) return const [PaymentChannel.qris];
  return const [
    PaymentChannel.bni,
    PaymentChannel.bri,
    PaymentChannel.mandiri,
    PaymentChannel.permata,
    PaymentChannel.cimb,
  ];
}

bool isChannelAllowedForAmount(PaymentChannel channel, int grandTotalIdr) =>
    availablePaymentChannels(grandTotalIdr).contains(channel);

class CheckoutTotals {
  const CheckoutTotals({
    required this.grandTotalBeforeFee,
    required this.gatewayFee,
    required this.gatewayFeeWaived,
    required this.gatewayFeeCharged,
    required this.grandTotal,
    required this.effectiveDiscount,
  });

  final int grandTotalBeforeFee;
  final int gatewayFee;
  final bool gatewayFeeWaived;
  final int gatewayFeeCharged;
  final int grandTotal;
  final int effectiveDiscount;
}

/// Mirrors `computeCheckoutTotals`.
CheckoutTotals computeCheckoutTotals({
  required int itemsSubtotal,
  required int shippingTotal,
  required int insuranceTotal,
  required PaymentMethod paymentMethod,
  required PaymentChannel? paymentChannel,
  required AppliedCoupon? appliedCoupon,
}) {
  final grandTotalBeforeFee = itemsSubtotal + shippingTotal + insuranceTotal;

  final gatewayFee =
      paymentMethod == PaymentMethod.wallet ||
          paymentChannel == null ||
          grandTotalBeforeFee <= 0
      ? 0
      : platformBuyerFeeFlatIdr;

  final gatewayFeeWaived =
      (appliedCoupon?.waivesGatewayFee ?? false) && paymentChannel != null;

  final gatewayFeeCharged = paymentMethod == PaymentMethod.wallet
      ? 0
      : gatewayFeeWaived
      ? 0
      : gatewayFee;

  final grandTotal = grandTotalBeforeFee + gatewayFeeCharged;

  final effectiveDiscount = gatewayFeeWaived
      ? gatewayFee
      : (appliedCoupon?.discountAmount ?? 0);

  return CheckoutTotals(
    grandTotalBeforeFee: grandTotalBeforeFee,
    gatewayFee: gatewayFee,
    gatewayFeeWaived: gatewayFeeWaived,
    gatewayFeeCharged: gatewayFeeCharged,
    grandTotal: grandTotal,
    effectiveDiscount: effectiveDiscount,
  );
}
