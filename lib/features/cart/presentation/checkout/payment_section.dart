import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../repository/models/checkout_models.dart';
import 'payment_method_picker.dart';

/// Ports `features/checkout/ui/PaymentSection.tsx`.
class PaymentSection extends StatelessWidget {
  const PaymentSection({
    super.key,
    required this.grandTotalBeforeFee,
    required this.paymentMethod,
    required this.paymentChannel,
    required this.walletBalance,
    required this.onPick,
  });

  final int grandTotalBeforeFee;
  final PaymentMethod paymentMethod;
  final PaymentChannel? paymentChannel;
  final int walletBalance;
  final ValueChanged<PaymentPick> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Metode Pembayaran',
            style: AppTypography.bodySemibold(colors.onSurface),
          ),
          const SizedBox(height: 10),
          PaymentMethodPicker(
            grandTotal: grandTotalBeforeFee,
            paymentMethod: paymentMethod,
            selectedChannel: paymentChannel,
            walletBalance: walletBalance,
            onPick: onPick,
          ),
          if (paymentMethod == PaymentMethod.wallet) ...[
            const SizedBox(height: 8),
            Text(
              'Saldo akan langsung dikurangi saat kamu konfirmasi.',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}
