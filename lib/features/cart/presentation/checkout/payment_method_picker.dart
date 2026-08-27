import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/checkout_pricing.dart';
import '../../repository/models/checkout_models.dart';

/// Result of the payment method sheet: either a xendit channel or "wallet".
sealed class PaymentPick {}

class XenditPick implements PaymentPick {
  XenditPick(this.channel);
  final PaymentChannel channel;
}

class WalletPick implements PaymentPick {}

/// Ports `components/shared/payment-method-picker.tsx` — a trigger button
/// that opens a bottom sheet listing wallet balance, QRIS, and VA banks,
/// grouped and gated by [grandTotal] the same way the web does.
class PaymentMethodPicker extends StatelessWidget {
  const PaymentMethodPicker({
    super.key,
    required this.grandTotal,
    required this.paymentMethod,
    required this.selectedChannel,
    required this.walletBalance,
    required this.onPick,
  });

  final int grandTotal;
  final PaymentMethod paymentMethod;
  final PaymentChannel? selectedChannel;
  final int walletBalance;
  final ValueChanged<PaymentPick> onPick;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<PaymentPick>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _PaymentMethodSheet(
        grandTotal: grandTotal,
        paymentMethod: paymentMethod,
        selectedChannel: selectedChannel,
        walletBalance: walletBalance,
      ),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final walletSelected = paymentMethod == PaymentMethod.wallet;
    final meta = selectedChannel == null
        ? null
        : paymentChannels.firstWhere((m) => m.channel == selectedChannel);

    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: (walletSelected || meta != null)
                ? colors.primary.withValues(alpha: 0.4)
                : context.borderColor,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (walletSelected || meta != null)
                    ? colors.primary.withValues(alpha: 0.1)
                    : Theme.of(context).colorScheme.secondary,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(
                walletSelected
                    ? Icons.account_balance_wallet_outlined
                    : meta != null
                    ? (meta.group == PaymentChannelGroup.qr
                          ? Icons.qr_code
                          : Icons.credit_card)
                    : Icons.credit_card,
                size: 16,
                color: (walletSelected || meta != null)
                    ? colors.primary
                    : context.mutedForeground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    walletSelected
                        ? 'Bayar pakai Saldo'
                        : meta?.label ?? 'Pilih metode pembayaran',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  Text(
                    walletSelected
                        ? 'Saldo: ${formatRupiah(walletBalance)}'
                        : meta?.description ??
                              (grandTotal < qrisMaxIdr
                                  ? 'QRIS tersedia'
                                  : 'Virtual Account tersedia'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodSheet extends StatelessWidget {
  const _PaymentMethodSheet({
    required this.grandTotal,
    required this.paymentMethod,
    required this.selectedChannel,
    required this.walletBalance,
  });

  final int grandTotal;
  final PaymentMethod paymentMethod;
  final PaymentChannel? selectedChannel;
  final int walletBalance;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final allowed = availablePaymentChannels(grandTotal).toSet();
    final qr = paymentChannels
        .where((m) => m.group == PaymentChannelGroup.qr)
        .toList();
    final va = paymentChannels
        .where((m) => m.group == PaymentChannelGroup.va)
        .toList();
    final walletInsufficient = walletBalance < grandTotal;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Metode Pembayaran',
                    style: AppTypography.h3(colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Total ${formatRupiah(grandTotal)}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  _SectionHeader(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Saldo',
                    caption: 'Bayar pakai saldo pokepedia.id',
                  ),
                  InkWell(
                    onTap: walletInsufficient
                        ? null
                        : () => Navigator.of(context).pop(WalletPick()),
                    child: Opacity(
                      opacity: walletInsufficient ? 0.5 : 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: paymentMethod == PaymentMethod.wallet
                              ? colors.primary.withValues(alpha: 0.05)
                              : null,
                          border: Border(
                            bottom: BorderSide(color: context.borderColor),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 18,
                              color: context.mutedForeground,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bayar pakai Saldo',
                                    style: AppTypography.bodySmSemibold(
                                      colors.onSurface,
                                    ),
                                  ),
                                  Text.rich(
                                    TextSpan(
                                      text:
                                          'Saldo: ${formatRupiah(walletBalance)}',
                                      style: AppTypography.caption(
                                        context.mutedForeground,
                                      ),
                                      children: walletInsufficient
                                          ? [
                                              TextSpan(
                                                text: ' (saldo tidak cukup)',
                                                style: AppTypography.caption(
                                                  colors.error,
                                                ),
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _SelectedDot(
                              selected: paymentMethod == PaymentMethod.wallet,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _ChannelSection(
                    icon: Icons.qr_code,
                    title: 'QRIS',
                    caption: 'Bayar instan dengan QR',
                    unavailableHint:
                        'Tersedia untuk pembayaran < ${formatRupiah(qrisMaxIdr)}',
                    items: qr,
                    allowed: allowed,
                    selectedChannel: selectedChannel,
                  ),
                  _ChannelSection(
                    icon: Icons.credit_card,
                    title: 'Virtual Account',
                    caption: 'Transfer bank',
                    unavailableHint:
                        'Tersedia untuk pembayaran ≥ ${formatRupiah(qrisMaxIdr)}',
                    items: va,
                    allowed: allowed,
                    selectedChannel: selectedChannel,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.caption,
  });

  final IconData icon;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: context.mutedForeground),
          const SizedBox(width: 6),
          Text(
            title,
            style: AppTypography.captionSemibold(context.mutedForeground),
          ),
          Text(
            ' · $caption',
            style: AppTypography.caption(
              context.mutedForeground.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelSection extends StatelessWidget {
  const _ChannelSection({
    required this.icon,
    required this.title,
    required this.caption,
    required this.unavailableHint,
    required this.items,
    required this.allowed,
    required this.selectedChannel,
  });

  final IconData icon;
  final String title;
  final String caption;
  final String unavailableHint;
  final List<PaymentChannelMeta> items;
  final Set<PaymentChannel> allowed;
  final PaymentChannel? selectedChannel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasAnyAllowed = items.any((m) => allowed.contains(m.channel));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(icon: icon, title: title, caption: caption),
        if (!hasAnyAllowed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: context.mutedForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    unavailableHint,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ),
              ],
            ),
          )
        else
          for (final meta in items)
            if (allowed.contains(meta.channel))
              InkWell(
                onTap: () =>
                    Navigator.of(context).pop(XenditPick(meta.channel)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selectedChannel == meta.channel
                        ? colors.primary.withValues(alpha: 0.05)
                        : null,
                    border: Border(
                      bottom: BorderSide(color: context.borderColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          icon,
                          size: 15,
                          color: context.mutedForeground,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              meta.label,
                              style: AppTypography.bodySmSemibold(
                                colors.onSurface,
                              ),
                            ),
                            Text(
                              meta.description,
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _SelectedDot(selected: selectedChannel == meta.channel),
                    ],
                  ),
                ),
              ),
      ],
    );
  }
}

class _SelectedDot extends StatelessWidget {
  const _SelectedDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.primary : Colors.transparent,
        border: Border.all(
          color: selected ? colors.primary : context.borderColor,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: 13, color: colors.onPrimary)
          : null,
    );
  }
}
