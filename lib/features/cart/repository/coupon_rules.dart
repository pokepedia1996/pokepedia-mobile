import 'models/checkout_models.dart';

/// Ports `clientBlockReason` from `features/checkout/utils/coupon-eligibility.ts`.
///
/// Free shipping stays usable on saldo and before a channel is picked; the
/// fee waiver does not, since neither of those charges a fee to waive.
String? couponBlockReason(
  CouponType type, {
  required PaymentMethod paymentMethod,
  required PaymentChannel? paymentChannel,
  required int shippingTotal,
}) {
  switch (type) {
    case CouponType.waiveGatewayFee:
      if (paymentMethod == PaymentMethod.wallet) {
        return 'Tidak berlaku untuk pembayaran saldo';
      }
      if (paymentChannel == null) return 'Pilih metode pembayaran dulu';
      return null;
    case CouponType.freeShipping:
      if (shippingTotal <= 0) return 'Pilih kurir dulu';
      return null;
  }
}

/// The buyer's own coupon choices, per slot, made against one cart.
///
/// A slot that is absent is left to the default; one mapped to null was
/// declined on purpose. Ports `OverrideState` from `useCoupon.ts`.
class CouponOverrides {
  const CouponOverrides({required this.subtotal, this.slots = const {}});

  /// The items subtotal these choices were made against. A cart edit is the
  /// only thing that makes a declined promo offerable again.
  final int subtotal;
  final Map<CouponSlot, AppliedCoupon?> slots;

  Map<CouponSlot, AppliedCoupon?> activeFor(int itemsSubtotal) =>
      subtotal == itemsSubtotal ? slots : const {};

  CouponOverrides withSlot(
    CouponSlot slot,
    AppliedCoupon? coupon, {
    required int itemsSubtotal,
  }) => CouponOverrides(
    subtotal: itemsSubtotal,
    slots: {...activeFor(itemsSubtotal), slot: coupon},
  );

  bool chose(CouponSlot slot, int itemsSubtotal) =>
      activeFor(itemsSubtotal)[slot] != null;
}

/// Ports the derived `selection` in `useCoupon.ts`: the buyer's choice for
/// this cart, else the best eligible coupon the server listed for the slot.
///
/// A chosen coupon that has since disappeared from [catalog], turned
/// ineligible, or been blocked by the payment choice is dropped — the
/// catalog lists ineligible rows too, so a missing one means it died.
CouponSelection resolveCouponSelection({
  required List<AvailableCoupon> catalog,
  required CouponOverrides overrides,
  required int itemsSubtotal,
  required PaymentMethod paymentMethod,
  required PaymentChannel? paymentChannel,
  required int shippingTotal,
}) {
  if (catalog.isEmpty) return CouponSelection.empty;

  bool usable(AvailableCoupon coupon) =>
      coupon.eligible &&
      couponBlockReason(
            coupon.type,
            paymentMethod: paymentMethod,
            paymentChannel: paymentChannel,
            shippingTotal: shippingTotal,
          ) ==
          null;

  final active = overrides.activeFor(itemsSubtotal);
  AppliedCoupon? pick(CouponSlot slot) {
    if (active.containsKey(slot)) {
      final chosen = active[slot];
      if (chosen == null) return null;
      for (final live in catalog) {
        if (live.couponId == chosen.couponId) {
          return usable(live) ? chosen : null;
        }
      }
      return null;
    }
    for (final coupon in catalog) {
      if (coupon.slot == slot && usable(coupon)) return coupon.toApplied();
    }
    return null;
  }

  return CouponSelection(
    shipping: pick(CouponSlot.shipping),
    fee: pick(CouponSlot.fee),
  );
}
