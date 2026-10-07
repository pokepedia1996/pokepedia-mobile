import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/checkout_pricing.dart';
import '../../repository/models/checkout_models.dart';

/// Ports `features/checkout/components/sections/order-summary.tsx` — the
/// cost breakdown, the coupon slot, and the final "Bayar Sekarang" action.
class OrderSummary extends StatelessWidget {
  const OrderSummary({
    super.key,
    required this.itemsSubtotal,
    required this.shippingTotal,
    required this.insuranceTotal,
    required this.paymentMethod,
    required this.hasChannel,
    required this.totals,
    required this.coupons,
    required this.couponSlot,
    required this.submitting,
    required this.payDisabled,
    required this.onCheckout,
  });

  final int itemsSubtotal;
  final int shippingTotal;
  final int insuranceTotal;
  final PaymentMethod paymentMethod;
  final bool hasChannel;
  final CheckoutTotals totals;
  final CouponSelection coupons;

  /// The promo trigger, rendered between the fees and the total as web's
  /// `couponSlot` is.
  final Widget couponSlot;
  final bool submitting;
  final bool payDisabled;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final success = context.appSemantic.success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ringkasan',
            style: AppTypography.bodySemibold(colors.onSurface),
          ),
          const SizedBox(height: 12),
          _Row(label: 'Subtotal kartu', value: formatRupiah(itemsSubtotal)),
          _Row(label: 'Ongkos kirim', value: formatRupiah(shippingTotal)),
          if (totals.shippingDiscount > 0 && coupons.shipping != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _Row(
                label: 'Diskon ongkir',
                value: '- ${formatRupiah(totals.shippingDiscount)}',
                color: success,
              ),
            ),
          if (insuranceTotal > 0)
            _Row(
              label: 'Asuransi pengiriman',
              value: formatRupiah(insuranceTotal),
            ),
          if (paymentMethod == PaymentMethod.xendit)
            _Row(
              label: 'Biaya Platform',
              value: !hasChannel ? '-' : formatRupiah(totals.gatewayFee),
              strikethrough: totals.gatewayFeeWaived,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: context.borderColor),
          ),
          couponSlot,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: context.borderColor),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: AppTypography.bodySemibold(colors.onSurface),
              ),
              Text(
                formatRupiah(totals.grandTotal),
                style: AppTypography.bodySemibold(colors.primary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: payDisabled || submitting ? null : onCheckout,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: submitting
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Memproses...'),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('Bayar Sekarang'),
                      SizedBox(width: 6),
                      Icon(LucideIcons.arrowRight, size: 16),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.color,
    this.strikethrough = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    final labelColor = color ?? context.mutedForeground;
    final valueColor = color ?? context.appColors.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.bodySm(labelColor)),
          Text(
            value,
            style: AppTypography.bodySmSemibold(valueColor).copyWith(
              decoration: strikethrough ? TextDecoration.lineThrough : null,
              color: strikethrough
                  ? valueColor.withValues(alpha: 0.5)
                  : valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
