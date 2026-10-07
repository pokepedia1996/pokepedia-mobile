import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../../../shared/widgets/condition_badge.dart';
import '../../../../shared/widgets/seller_avatar.dart';
import '../../repository/checkout_pricing.dart';
import '../../repository/models/checkout_deal.dart';
import '../../repository/models/checkout_models.dart';
import '../../repository/models/cart_item.dart';
import 'courier_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One seller's items within the cart, plus their shipping/insurance
/// choices. Ports `features/checkout/ui/SellerGroupCard.tsx`, deals
/// (`DealItemGroup`) included.
class SellerGroupCard extends StatelessWidget {
  const SellerGroupCard({
    super.key,
    required this.items,
    this.deals = const [],
    required this.courierOptions,
    required this.selectedCourier,
    required this.onSelectCourier,
    required this.insuranceEnabled,
    required this.onToggleInsurance,
    required this.hasAddress,
    this.ratesLoading = false,
    this.ratesError,
    this.ratesReason,
    this.onRetryRates,
  });

  final List<CartItem> items;

  /// Accepted bid proposals from this seller, drawn under the cart lines at
  /// the price the deal fixed. A deal-only seller has no [items] at all.
  final List<CheckoutDeal> deals;
  final List<CourierOption> courierOptions;
  final CourierOption? selectedCourier;
  final ValueChanged<CourierOption> onSelectCourier;
  final bool insuranceEnabled;
  final ValueChanged<bool> onToggleInsurance;
  final bool hasAddress;

  /// Quote in flight for this seller. Ports the web card's `addressLoading`
  /// spinner state.
  final bool ratesLoading;

  /// Why the quote failed, if it did. Biteship is a live third-party call,
  /// so this is a normal outcome and needs a retry rather than a dead card.
  final String? ratesError;

  /// Why the quote came back short, which decides the empty-list copy.
  final RatesReason? ratesReason;
  final VoidCallback? onRetryRates;

  int get _subtotal =>
      items.fold(0, (sum, item) => sum + item.subtotal) +
      deals.fold(0, (sum, deal) => sum + deal.subtotal);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final first = items.firstOrNull?.listing;
    final deal = deals.firstOrNull;
    final storeName =
        first?.storeName ??
        (deal?.storeName?.isNotEmpty == true ? deal!.storeName! : 'Penjual');
    final storeImageUrl = first?.sellerImageUrl ?? deal?.storeLogoUrl;
    final cityName = first?.cityName ?? '';
    final mandatory = isInsuranceMandatory(_subtotal);
    final hasSelection = selectedCourier != null;
    final insuranceAvailable = selectedCourier?.insuranceAvailable ?? false;
    final mandatoryUnsupported =
        mandatory && hasSelection && !insuranceAvailable;
    final checkboxChecked =
        insuranceAvailable && (insuranceEnabled || mandatory);
    final checkboxDisabled = !insuranceAvailable || mandatory;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Seller header.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: 0.3),
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Row(
              children: [
                SellerAvatar(
                  name: storeName,
                  imageUrl: storeImageUrl,
                  size: 32,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              storeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySmSemibold(
                                colors.onSurface,
                              ),
                            ),
                          ),
                          if (first?.isVerified ?? false) ...[
                            const SizedBox(width: 4),
                            Icon(
                              LucideIcons.badgeCheck,
                              size: 14,
                              color: colors.primary,
                            ),
                          ],
                        ],
                      ),
                      if (cityName.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              LucideIcons.mapPin,
                              size: 12,
                              color: context.mutedForeground,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              cityName,
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Items.
          for (final item in items)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: CardArt(
                      imageUrl: item.listing.card.imageUrl,
                      borderRadius: AppRadius.sm,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.listing.card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ConditionBadge(condition: item.listing.condition),
                            Text(
                              'Qty: ${item.quantity}',
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatRupiah(item.subtotal),
                          style: AppTypography.bodySmSemibold(colors.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          for (final deal in deals)
            for (final line in deal.lines) _DealLineRow(line: line),

          // Shipping + insurance.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: 0.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pilih kurir',
                  style: AppTypography.captionSemibold(colors.onSurface),
                ),
                const SizedBox(height: 8),
                if (!hasAddress)
                  Text(
                    'Tambah alamat pengiriman dulu untuk melihat pilihan kurir.',
                    style: AppTypography.caption(context.mutedForeground),
                  )
                else if (ratesLoading)
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Mengambil tarif kurir...',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ],
                  )
                else if (ratesError != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ratesError!,
                        style: AppTypography.caption(colors.error),
                      ),
                      if (onRetryRates != null)
                        TextButton(
                          onPressed: onRetryRates,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Coba lagi'),
                        ),
                    ],
                  )
                else if (courierOptions.isEmpty)
                  Text(
                    emptyCourierMessage(ratesReason),
                    style: AppTypography.caption(context.mutedForeground),
                  )
                else ...[
                  if (ratesReason == RatesReason.sellerRestrictedPartial) ...[
                    Text(
                      partialCourierListHint,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    const SizedBox(height: 8),
                  ],
                  CourierPicker(
                    options: courierOptions,
                    selected: selectedCourier,
                    onSelect: onSelectCourier,
                  ),
                ],
                if (hasAddress && hasSelection) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: mandatoryUnsupported
                            ? colors.error.withValues(alpha: 0.4)
                            : context.borderColor,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Checkbox(
                            value: checkboxChecked,
                            onChanged: checkboxDisabled
                                ? null
                                : (v) => onToggleInsurance(v ?? false),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Aktifkan asuransi pengiriman',
                                      style: AppTypography.captionSemibold(
                                        colors.onSurface,
                                      ),
                                    ),
                                  ),
                                  if (insuranceAvailable &&
                                      (selectedCourier?.insuranceFee ?? 0) > 0)
                                    Text(
                                      '+ ${formatRupiah(selectedCourier!.insuranceFee)}',
                                      style: AppTypography.captionSemibold(
                                        colors.primary,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                mandatoryUnsupported
                                    ? 'Pesanan di atas ${formatRupiah(insuranceMandatoryThresholdIdr)} wajib pakai kurir yang mendukung asuransi. Pilih kurir lain.'
                                    : mandatory && insuranceAvailable
                                    ? 'Wajib untuk pesanan di atas ${formatRupiah(insuranceMandatoryThresholdIdr)}.'
                                    : insuranceAvailable
                                    ? 'Lindungi paket dari kehilangan atau kerusakan saat pengiriman.'
                                    : 'Kurir ini tidak mendukung asuransi pengiriman. Pilih kurir lain untuk mengaktifkan.',
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of an accepted proposal. Ports `DealItemGroup`'s row: the card,
/// its condition and quantity, and the price the deal settled on.
class _DealLineRow extends StatelessWidget {
  const _DealLineRow({required this.line});

  final CheckoutDealLine line;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final condition = line.condition;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: CardArt(imageUrl: line.imageUrl, borderRadius: AppRadius.sm),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.cardName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (condition != null) ConditionBadge(condition: condition),
                    Text(
                      'Qty: ${line.quantity}',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    Text(
                      'Proposal diterima',
                      style: AppTypography.captionSemibold(colors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  formatRupiah(line.subtotal),
                  style: AppTypography.bodySmSemibold(colors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
