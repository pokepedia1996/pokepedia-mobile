import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../repository/checkout_dummy_data.dart';
import '../../repository/models/checkout_models.dart';

/// Ports `components/address/checkout-address-picker.tsx` — the selected
/// address card plus a "Ganti" bottom sheet to pick from saved addresses.
class CheckoutAddressPicker extends StatelessWidget {
  const CheckoutAddressPicker({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final CheckoutAddress? selected;
  final ValueChanged<CheckoutAddress> onSelect;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<CheckoutAddress>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => _AddressListSheet(selectedId: selected?.id),
    );
    if (picked != null) onSelect(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final address = selected;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ALAMAT PENGIRIMAN',
            style: AppTypography.captionSemibold(
              context.mutedForeground,
            ).copyWith(letterSpacing: 0.4),
          ),
          const SizedBox(height: 8),
          if (address == null)
            InkWell(
              onTap: () => _openPicker(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.4),
                  ),
                  color: colors.primary.withValues(alpha: 0.05),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+ Tambah Alamat',
                  style: AppTypography.bodySmSemibold(colors.primary),
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            LucideIcons.mapPin,
                            size: 16,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${address.label} · ${address.contactName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySmSemibold(
                                colors.onSurface,
                              ),
                            ),
                          ),
                          if (address.isPrimary) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: Text(
                                'Utama',
                                style: AppTypography.caption(colors.primary),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${address.fullAddress}, ${address.district}, '
                        '${address.cityName}, ${address.provinceName} '
                        '${address.postalCode}',
                        style: AppTypography.caption(colors.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        address.contactPhone,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _openPicker(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('Ganti'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AddressListSheet extends StatelessWidget {
  const _AddressListSheet({required this.selectedId});

  final int? selectedId;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            Text('Pilih Alamat', style: AppTypography.h3(colors.onSurface)),
            const SizedBox(height: 12),
            for (final address in CheckoutDummyData.addresses) ...[
              InkWell(
                onTap: () => Navigator.of(context).pop(address),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: address.id == selectedId
                          ? colors.primary
                          : context.borderColor,
                      width: address.id == selectedId ? 1.5 : 1,
                    ),
                    color: address.id == selectedId
                        ? colors.primary.withValues(alpha: 0.05)
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${address.label} · ${address.contactName}',
                                  style: AppTypography.bodySmSemibold(
                                    colors.onSurface,
                                  ),
                                ),
                                if (address.isPrimary) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.full,
                                      ),
                                    ),
                                    child: Text(
                                      'Utama',
                                      style: AppTypography.caption(
                                        colors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${address.fullAddress}, ${address.district}, '
                              '${address.cityName}',
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (address.id == selectedId)
                        Icon(
                          LucideIcons.circleCheckBig,
                          color: colors.primary,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              ),
            ],
            OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Fitur tambah alamat segera hadir'),
                  ),
                );
              },
              child: const Text('+ Tambah Alamat Baru'),
            ),
          ],
        ),
      ),
    );
  }
}
