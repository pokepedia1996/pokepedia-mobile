import 'models/checkout_models.dart';

/// Pricing constants and pure calculations for the checkout flow. Ports
/// `features/checkout/model/pricing.ts` and the relevant bits of
/// `lib/payments/pricing.ts`.
const insuranceMandatoryThresholdIdr = 500000;
const qrisMaxIdr = 1450000;

bool isInsuranceMandatory(int sellerSubtotal) =>
    sellerSubtotal > insuranceMandatoryThresholdIdr;

/// Mirrors `getAvailablePaymentChannels`: the channels [options] offers at
/// this total. The Xendit default is QRIS below the threshold and VA banks
/// at or above it; the server's own rules replace it once they're in.
List<PaymentChannel> availablePaymentChannels(
  int grandTotalIdr, [
  PaymentOptions options = PaymentOptions.xenditDefault,
]) => options.channelsFor(grandTotalIdr);

bool isChannelAllowedForAmount(
  PaymentChannel channel,
  int grandTotalIdr, [
  PaymentOptions options = PaymentOptions.xenditDefault,
]) => availablePaymentChannels(grandTotalIdr, options).contains(channel);

/// What checkout preselects for a buyer who hasn't chosen for themselves.
///
/// 1. Saldo, whenever it covers the bill — it settles instantly.
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
({PaymentMethod method, PaymentChannel? channel}) autoSelectPayment({
  required int grandTotalIdr,
  required int walletBalance,
  int? walletAmountDue,
  PaymentChannel? lastPaidChannel,
  PaymentOptions options = PaymentOptions.xenditDefault,
}) {
  if (walletBalance >= (walletAmountDue ?? grandTotalIdr)) {
    return (method: PaymentMethod.wallet, channel: null);
  }

  final available = availablePaymentChannels(grandTotalIdr, options);
  final channel = lastPaidChannel != null && available.contains(lastPaidChannel)
      ? lastPaidChannel
      : available.firstOrNull;
  return (method: PaymentMethod.xendit, channel: channel);
}

/// What the buyer pays. There is no buyer fee on any method: web dropped the
/// Rp2.000 "Biaya Platform" (pokepedia-web e85673b8), and the lock RPCs
/// invoice the total less the shipping discount for every new cart.
class CheckoutTotals {
  const CheckoutTotals({
    required this.totalBeforeDiscount,
    required this.shippingDiscount,
    required this.grandTotal,
  });

  /// Items, shipping and insurance: what the payment channel rules are
  /// judged against, as the server judges them.
  final int totalBeforeDiscount;
  final int shippingDiscount;

  /// What the buyer pays, by the gateway or from saldo alike.
  final int grandTotal;

  /// The "Hemat" figure: the free-shipping discount, now the only one.
  int get totalDiscount => shippingDiscount;

  /// What a saldo payment debits; the same as [grandTotal].
  int get walletAmountDue => grandTotal;
}

/// Mirrors `shippingDiscountFor` (and `_coupon_discount.sql` behind it):
/// derived from the coupon's own cap, never from a cached amount.
int shippingDiscountFor(AppliedCoupon? coupon, int shippingTotal) {
  if (coupon == null) return 0;
  final cap = coupon.value ?? 0;
  return shippingTotal < cap ? shippingTotal : cap;
}

/// Mirrors `computeCheckoutTotals` in `features/checkout/domain/pricing.ts`,
/// which mirrors the invoice math in the lock RPCs — disagree with them and
/// `commit_cart_match` rejects the payment.
CheckoutTotals computeCheckoutTotals({
  required int itemsSubtotal,
  required int shippingTotal,
  required int insuranceTotal,
  CouponSelection coupons = CouponSelection.empty,
}) {
  final totalBeforeDiscount = itemsSubtotal + shippingTotal + insuranceTotal;
  final shippingDiscount = shippingDiscountFor(coupons.shipping, shippingTotal);
  return CheckoutTotals(
    totalBeforeDiscount: totalBeforeDiscount,
    shippingDiscount: shippingDiscount,
    grandTotal: _atLeastZero(totalBeforeDiscount - shippingDiscount),
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
