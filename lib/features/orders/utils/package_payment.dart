/// One settlement's share of what a package cost the buyer — web's
/// `PackagePaymentLine` in `lib/orders/package-payment.ts`.
class PackagePaymentLine {
  const PackagePaymentLine({
    required this.subtotal,
    this.shippingCost = 0,
    this.shippingDiscount = 0,
    this.insurance = 0,
    this.cancelled = false,
  });

  final int subtotal;

  /// `settlements.shipping_cost`, gross of any ongkir coupon.
  final int shippingCost;

  /// `settlements.shipping_discount_idr`.
  final int shippingDiscount;

  /// `settlements.insurance_fee_idr`.
  final int insurance;

  /// `order_items.status == 'cancelled'`.
  final bool cancelled;
}

/// `PackageCheckoutFees` — the checkout-level columns on `carts`.
class PackageCheckoutFees {
  const PackageCheckoutFees({
    required this.totalAmount,
    required this.gatewayFee,
    required this.gatewayFeeCharged,
  });

  /// Reads an embedded `carts(total_amount, gateway_fee, gateway_fee_charged)`
  /// row; null when the buyer's session couldn't see the cart.
  static PackageCheckoutFees? fromRow(Map<String, dynamic>? row) {
    final total = row?['total_amount'] as num?;
    if (row == null || total == null) return null;
    return PackageCheckoutFees(
      totalAmount: total.toInt(),
      gatewayFee: (row['gateway_fee'] as num?)?.toInt() ?? 0,
      gatewayFeeCharged: (row['gateway_fee_charged'] as num?)?.toInt() ?? 0,
    );
  }

  final int totalAmount;
  final int gatewayFee;
  final int gatewayFeeCharged;
}

/// `PackagePaymentBreakdown`.
class PackagePaymentBreakdown {
  const PackagePaymentBreakdown({
    required this.subtotal,
    required this.shippingGross,
    required this.shippingDiscount,
    required this.insurance,
    required this.showCheckoutFee,
    required this.platformFee,
    required this.platformFeeWaived,
    required this.paidTotal,
    required this.cancelledCount,
    required this.cancelledAmount,
    required this.originalPaidTotal,
  });

  final int subtotal;
  final int shippingGross;
  final int shippingDiscount;
  final int insurance;
  final bool showCheckoutFee;
  final int platformFee;
  final int platformFeeWaived;
  final int paidTotal;
  final int cancelledCount;
  final int cancelledAmount;
  final int originalPaidTotal;

  bool get isPlatformFeeWaived => platformFeeWaived >= platformFee;
}

class _LineTotals {
  int subtotal = 0;
  int shippingGross = 0;
  int shippingDiscount = 0;
  int insurance = 0;

  int get net => subtotal + shippingGross - shippingDiscount + insurance;
}

int _nonNegative(int n) => n < 0 ? 0 : n;

_LineTotals _sumLines(Iterable<PackagePaymentLine> lines) {
  final totals = _LineTotals();
  for (final line in lines) {
    totals.subtotal += line.subtotal;
    totals.shippingGross += line.shippingCost;
    final discount = _nonNegative(line.shippingDiscount);
    totals.shippingDiscount += discount < line.shippingCost
        ? discount
        : line.shippingCost;
    totals.insurance += line.insurance;
  }
  return totals;
}

/// Ports `computePackagePayment`.
///
/// The checkout's gateway fee is only attributable to this package when the
/// package is the whole checkout, i.e. `carts.total_amount` equals its gross.
PackagePaymentBreakdown computePackagePayment(
  List<PackagePaymentLine> lines,
  PackageCheckoutFees? checkout,
) {
  final all = _sumLines(lines);
  final cancelledLines = lines.where((line) => line.cancelled).toList();
  final active = _sumLines(lines.where((line) => !line.cancelled));

  final grossTotal = all.subtotal + all.shippingGross + all.insurance;
  final attributable = checkout != null && checkout.totalAmount == grossTotal
      ? checkout
      : null;
  final showCheckoutFee = attributable != null;
  final platformFee = _nonNegative(attributable?.gatewayFee ?? 0);
  final feeCharged = _nonNegative(attributable?.gatewayFeeCharged ?? 0);

  return PackagePaymentBreakdown(
    subtotal: active.subtotal,
    shippingGross: active.shippingGross,
    shippingDiscount: active.shippingDiscount,
    insurance: active.insurance,
    showCheckoutFee: showCheckoutFee,
    platformFee: platformFee,
    platformFeeWaived: _nonNegative(platformFee - feeCharged),
    paidTotal: active.net + feeCharged,
    cancelledCount: cancelledLines.length,
    cancelledAmount: _sumLines(cancelledLines).net,
    originalPaidTotal: all.net + feeCharged,
  );
}

/// Ports `cartChargedAmount` in `lib/checkout/charged-amount.ts`:
/// `total_amount` is the pre-coupon, pre-fee gross, `invoice_amount` is what
/// the buyer was actually charged. Null rather than web's 0 when neither is
/// set, so a caller can fall back to summing the lines.
int? cartChargedAmount(Map<String, dynamic> cart) =>
    ((cart['invoice_amount'] ?? cart['total_amount']) as num?)?.toInt();
