import 'models/checkout_models.dart';

/// Pricing constants and pure calculations for the checkout flow. Ports
/// `features/checkout/model/pricing.ts` and the relevant bits of
/// `lib/payments/pricing.ts`.
const insuranceMandatoryThresholdIdr = 500000;

/// The server dropped the Rp2.000 buyer fee on 2026-10-21
/// (`compute_buyer_gateway_fee` returns 0); kept as a constant so the
/// fee-waiver coupon plumbing still compiles.
const platformBuyerFeeFlatIdr = 0;
const qrisMaxIdr = 1450000;

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

/// What checkout preselects for a buyer who hasn't chosen for themselves.
///
/// 1. Saldo, whenever it covers the bill — it settles instantly and pays no
///    gateway fee.
/// 2. Otherwise the gateway. Which channels exist is decided by the amount,
///    not here: under [qrisMaxIdr] only QRIS is offered, at or above it only
///    the VA banks. So "fall back to QRIS" and "a big bill goes to VA" turn
///    out to be the same rule read from opposite ends.
/// 3. Among the VA banks, [lastPaidChannel] — what the buyer actually paid
///    with last time — in preference to whichever heads the list.
///
/// [walletAmountDue] is what saldo would actually be debited — the total
/// less any free-shipping discount, as [CheckoutTotals.walletAmountDue]
/// computes it. It defaults to [grandTotalIdr], which still decides which
/// gateway channels exist.
///
/// [holdsFeeWaiver] blocks the jump to Saldo: a coupon that waives the
/// gateway fee is worth nothing on a method that never charged one, and
/// voiding a coupon the buyer just applied is not a default's job.
({PaymentMethod method, PaymentChannel? channel}) autoSelectPayment({
  required int grandTotalIdr,
  required int walletBalance,
  int? walletAmountDue,
  PaymentChannel? lastPaidChannel,
  bool holdsFeeWaiver = false,
}) {
  if (walletBalance >= (walletAmountDue ?? grandTotalIdr) && !holdsFeeWaiver) {
    return (method: PaymentMethod.wallet, channel: null);
  }

  final available = availablePaymentChannels(grandTotalIdr);
  final channel = lastPaidChannel != null && available.contains(lastPaidChannel)
      ? lastPaidChannel
      : available.first;
  return (method: PaymentMethod.xendit, channel: channel);
}

class CheckoutTotals {
  const CheckoutTotals({
    required this.grandTotalBeforeFee,
    required this.gatewayFee,
    required this.gatewayFeeWaived,
    required this.gatewayFeeCharged,
    required this.shippingDiscount,
    required this.totalDiscount,
    required this.grandTotal,
    required this.walletAmountDue,
  });

  final int grandTotalBeforeFee;
  final int gatewayFee;
  final bool gatewayFeeWaived;
  final int gatewayFeeCharged;
  final int shippingDiscount;

  /// The free-shipping discount plus the waived fee — the "Hemat" figure.
  final int totalDiscount;
  final int grandTotal;

  /// What a saldo payment debits: no gateway fee, less the shipping discount.
  final int walletAmountDue;
}

/// Mirrors `shippingDiscountFor` (and `_coupon_discount.sql` behind it):
/// derived from the coupon's own cap, never from a cached amount.
int shippingDiscountFor(AppliedCoupon? coupon, int shippingTotal) {
  if (coupon == null) return 0;
  final cap = coupon.value ?? 0;
  return shippingTotal < cap ? shippingTotal : cap;
}

/// Mirrors `computeCheckoutTotals` in `features/checkout/utils/pricing.ts`,
/// which mirrors the invoice math in the lock RPCs — disagree with them and
/// `commit_cart_match` rejects the payment.
CheckoutTotals computeCheckoutTotals({
  required int itemsSubtotal,
  required int shippingTotal,
  required int insuranceTotal,
  required PaymentMethod paymentMethod,
  required PaymentChannel? paymentChannel,
  CouponSelection coupons = CouponSelection.empty,
}) {
  final grandTotalBeforeFee = itemsSubtotal + shippingTotal + insuranceTotal;

  final gatewayFee =
      paymentMethod == PaymentMethod.wallet ||
          paymentChannel == null ||
          grandTotalBeforeFee <= 0
      ? 0
      : platformBuyerFeeFlatIdr;

  final gatewayFeeWaived =
      coupons.fee != null &&
      paymentChannel != null &&
      paymentMethod != PaymentMethod.wallet;

  final gatewayFeeCharged = paymentMethod == PaymentMethod.wallet
      ? 0
      : gatewayFeeWaived
      ? 0
      : gatewayFee;

  final shippingDiscount = shippingDiscountFor(coupons.shipping, shippingTotal);

  final grandTotal = _atLeastZero(
    grandTotalBeforeFee + gatewayFeeCharged - shippingDiscount,
  );

  return CheckoutTotals(
    grandTotalBeforeFee: grandTotalBeforeFee,
    gatewayFee: gatewayFee,
    gatewayFeeWaived: gatewayFeeWaived,
    gatewayFeeCharged: gatewayFeeCharged,
    shippingDiscount: shippingDiscount,
    totalDiscount: shippingDiscount + (gatewayFeeWaived ? gatewayFee : 0),
    grandTotal: grandTotal,
    walletAmountDue: _atLeastZero(grandTotalBeforeFee - shippingDiscount),
  );
}

int _atLeastZero(int value) => value < 0 ? 0 : value;

/// Smallest cash remainder the server leaves for a Xendit invoice, mirroring
/// web's `KOIN_MIN_CASH_REMAINDER_IDR`.
const koinMinCashRemainder = 1500;

/// Display-only preview of the Koin the server will take: it applies
/// `min(spendable Koin, invoice amount)` after locking the cart, then takes
/// less Koin when the cash left would be between Rp1 and [minRemainder].
int koinAppliedFor({
  required bool useKoin,
  required int koinBalance,
  required int total,
  int minRemainder = 0,
}) {
  if (!useKoin || koinBalance <= 0 || total <= 0) return 0;
  final koin = koinBalance < total ? koinBalance : total;
  final remainder = total - koin;
  if (remainder > 0 && remainder < minRemainder) {
    final reduced = total - minRemainder;
    return reduced < 0 ? 0 : reduced;
  }
  return koin;
}
