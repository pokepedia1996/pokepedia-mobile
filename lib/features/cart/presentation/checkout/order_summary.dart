import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/checkout_pricing.dart';
import '../../repository/models/checkout_models.dart';

/// Ports `features/checkout/ui/OrderSummary.tsx` — the cost breakdown,
/// coupon input, and the final "Bayar Sekarang" action.
class OrderSummary extends StatefulWidget {
  const OrderSummary({
    super.key,
    required this.itemsSubtotal,
    required this.shippingTotal,
    required this.insuranceTotal,
    required this.paymentMethod,
    required this.hasChannel,
    required this.totals,
    required this.appliedCoupon,
    required this.couponInput,
    required this.onCouponInputChanged,
    required this.couponLoading,
    required this.couponApplyDisabled,
    required this.onApplyCoupon,
    required this.onRemoveCoupon,
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
  final AppliedCoupon? appliedCoupon;
  final String couponInput;
  final ValueChanged<String> onCouponInputChanged;
  final bool couponLoading;
  final bool couponApplyDisabled;
  final VoidCallback onApplyCoupon;
  final VoidCallback onRemoveCoupon;
  final bool submitting;
  final bool payDisabled;
  final VoidCallback onCheckout;

  @override
  State<OrderSummary> createState() => _OrderSummaryState();
}

class _OrderSummaryState extends State<OrderSummary> {
  late final _controller = TextEditingController(text: widget.couponInput);

  @override
  void didUpdateWidget(covariant OrderSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.couponInput != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.couponInput,
        selection: TextSelection.collapsed(offset: widget.couponInput.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final totals = widget.totals;
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
          _Row(
            label: 'Subtotal kartu',
            value: formatRupiah(widget.itemsSubtotal),
          ),
          _Row(
            label: 'Ongkos kirim',
            value: formatRupiah(widget.shippingTotal),
          ),
          if (widget.insuranceTotal > 0)
            _Row(
              label: 'Asuransi pengiriman',
              value: formatRupiah(widget.insuranceTotal),
            ),
          if (widget.paymentMethod == PaymentMethod.xendit)
            _Row(
              label: 'Biaya Platform',
              value: !widget.hasChannel ? '-' : formatRupiah(totals.gatewayFee),
              strikethrough: totals.gatewayFeeWaived,
            ),
          if (widget.appliedCoupon != null && !totals.gatewayFeeWaived)
            _Row(
              label: 'Diskon (${widget.appliedCoupon!.code})',
              value: '- ${formatRupiah(totals.effectiveDiscount)}',
              color: success,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: context.borderColor),
          ),
          if (widget.appliedCoupon != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.appliedCoupon!.code,
                          style: AppTypography.captionSemibold(success),
                        ),
                        Text(
                          'Hemat ${formatRupiah(totals.effectiveDiscount)}',
                          style: AppTypography.caption(success),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onRemoveCoupon,
                    child: Text(
                      'Lepas',
                      style: AppTypography.captionSemibold(success),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (v) {
                      final cleaned = v.toUpperCase().replaceAll(
                        RegExp(r'[^A-Z0-9_-]'),
                        '',
                      );
                      widget.onCouponInputChanged(
                        cleaned.length > 40
                            ? cleaned.substring(0, 40)
                            : cleaned,
                      );
                    },
                    style: AppTypography.bodySm(colors.onSurface),
                    decoration: const InputDecoration(
                      hintText: 'gunakan POKEPEDIA',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: widget.couponApplyDisabled || widget.couponLoading
                      ? null
                      : widget.onApplyCoupon,
                  child: widget.couponLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Pakai'),
                ),
              ],
            ),
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
            onPressed: widget.payDisabled || widget.submitting
                ? null
                : widget.onCheckout,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: widget.submitting
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
