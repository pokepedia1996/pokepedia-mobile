import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/coupon_rules.dart';
import '../../repository/models/checkout_models.dart';
import '../../usecase/checkout_notifier.dart';

/// Ports `benefitHeadline` from `features/checkout/utils/coupon-copy.ts`.
String couponBenefitHeadline(CouponType type, int? value) => switch (type) {
  CouponType.freeShipping => 'Gratis ongkir s/d ${formatRupiah(value ?? 0)}',
  CouponType.waiveGatewayFee => 'Bebas biaya platform',
};

/// Ports `termsLine`.
String couponTermsLine(int minPurchase) => minPurchase > 0
    ? 'Min. belanja ${formatRupiah(minPurchase)}'
    : 'Tanpa minimum belanja';

/// `URGENT_EXPIRY_DAYS` in `coupon-copy.ts`.
const _urgentExpiryDays = 3;

/// Ports `expiryLabel`.
({String text, bool urgent}) couponExpiryLabel(
  DateTime validUntil, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final until = validUntil.toLocal();
  final days =
      (until.difference(today).inMilliseconds / Duration.millisecondsPerDay)
          .ceil();
  if (days <= _urgentExpiryDays) {
    return (
      text: days <= 1 ? 'Berakhir hari ini' : 'Sisa $days hari',
      urgent: true,
    );
  }
  // Without the year a next-year expiry reads the same as one ending soon.
  final date = until.year == today.year
      ? formatShortDateId(until)
      : formatSaleDate(until);
  return (text: 's/d $date', urgent: false);
}

/// Ports `ineligibleLabel`.
String couponIneligibleLabel(AvailableCoupon coupon, int itemsSubtotal) {
  switch (coupon.reason) {
    case CouponIneligibleReason.minPurchase:
      final shortfall = coupon.minPurchase - itemsSubtotal;
      return 'Kurang ${formatRupiah(shortfall < 0 ? 0 : shortfall)} lagi';
    case CouponIneligibleReason.notApplicable:
      return coupon.type == CouponType.freeShipping
          ? 'Pilih kurir dulu'
          : 'Tidak berlaku untuk pembayaran saldo';
    case CouponIneligibleReason.usageLimit:
      return 'Kuota promo habis';
    case CouponIneligibleReason.perUserLimit:
      return 'Kuota kamu sudah habis';
    case null:
      return 'Tidak bisa dipakai sekarang';
  }
}

/// Ports `features/checkout/components/sections/coupon-section.tsx`: one
/// trigger summarising both coupon slots, opening the two-slot picker.
class CouponSection extends ConsumerWidget {
  const CouponSection({super.key});

  Future<void> _open(BuildContext context, CheckoutNotifier notifier) {
    notifier.loadCouponCatalog();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const _CouponPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final state = ref.watch(checkoutProvider);
    final notifier = ref.watch(checkoutProvider.notifier);
    final selection = notifier.coupons;
    final filled = [
      for (final slot in CouponSlot.values)
        if (selection[slot] case final coupon?) coupon,
    ];
    final availableCount = state.couponCatalog.where((c) => c.eligible).length;

    final headline = switch (filled) {
      [] => 'Pakai promo',
      [final only] => couponBenefitHeadline(only.type, only.value),
      _ => '${filled.length} promo dipakai',
    };
    final subline = state.couponsLoading && state.couponCatalog.isEmpty
        ? 'Memuat promo...'
        : filled.isNotEmpty
        ? 'Hemat ${formatRupiah(notifier.totals.totalDiscount)}'
        : availableCount > 0
        ? '$availableCount promo tersedia'
        : 'Cek promo yang tersedia';
    final active = filled.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _open(context, notifier),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: active
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
                    color: active
                        ? colors.primary.withValues(alpha: 0.1)
                        : Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    LucideIcons.ticket,
                    size: 16,
                    color: active ? colors.primary : context.mutedForeground,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                      Text(
                        subline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: context.mutedForeground,
                ),
              ],
            ),
          ),
        ),
        if (state.couponNotice != null) ...[
          const SizedBox(height: 6),
          Text(state.couponNotice!, style: AppTypography.caption(colors.error)),
        ],
      ],
    );
  }
}

/// Ports `coupon-picker.tsx`. Reads the notifier live, so a tap shows its
/// effect on the slot and the saving without closing the sheet.
class _CouponPickerSheet extends ConsumerWidget {
  const _CouponPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final state = ref.watch(checkoutProvider);
    final notifier = ref.watch(checkoutProvider.notifier);
    final selection = notifier.coupons;
    final itemsSubtotal = notifier.itemsSubtotal;
    final shippingTotal = notifier.shippingTotal;
    final totalSaving = notifier.totals.totalDiscount;
    final catalog = state.couponCatalog;

    // Fixed slot order keeps the list from reshuffling when eligibility flips.
    final ordered = [
      for (final slot in CouponSlot.values)
        ...catalog.where((c) => c.slot == slot),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
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
                    'Pakai promo',
                    style: AppTypography.h3(colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Promo yang bisa kamu pakai untuk pesanan ini',
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
                  if (state.couponsError)
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Gagal memuat daftar promo.',
                              style: AppTypography.bodySm(colors.onSurface),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                notifier.loadCouponCatalog(force: true),
                            child: const Text('Coba lagi'),
                          ),
                        ],
                      ),
                    ),
                  if (state.couponsLoading && catalog.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  if (!state.couponsLoading &&
                      !state.couponsError &&
                      catalog.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 32,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            LucideIcons.ticket,
                            size: 40,
                            color: context.mutedForeground,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Belum ada promo untuk kamu',
                            style: AppTypography.bodySmSemibold(
                              colors.onSurface,
                            ),
                          ),
                          Text(
                            'Promo baru akan muncul di sini.',
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final coupon in ordered)
                    _CouponRow(
                      coupon: coupon,
                      itemsSubtotal: itemsSubtotal,
                      selected:
                          selection[coupon.slot]?.couponId == coupon.couponId,
                      blockedReason: couponBlockReason(
                        coupon.type,
                        paymentMethod: state.paymentMethod,
                        paymentChannel: state.paymentChannel,
                        shippingTotal: shippingTotal,
                      ),
                      onToggle: () =>
                          selection[coupon.slot]?.couponId == coupon.couponId
                          ? notifier.clearCouponSlot(coupon.slot)
                          : notifier.selectCoupon(coupon),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (totalSaving > 0) ...[
                    Text(
                      'Total hemat ${formatRupiah(totalSaving)}',
                      style: AppTypography.bodySmSemibold(
                        context.appSemantic.success,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Selesai'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ports `coupon-row.tsx`.
class _CouponRow extends StatelessWidget {
  const _CouponRow({
    required this.coupon,
    required this.itemsSubtotal,
    required this.selected,
    required this.blockedReason,
    required this.onToggle,
  });

  final AvailableCoupon coupon;
  final int itemsSubtotal;
  final bool selected;
  final String? blockedReason;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final usable = coupon.eligible && blockedReason == null;
    final validUntil = coupon.validUntil;
    final expiry = validUntil == null ? null : couponExpiryLabel(validUntil);

    return InkWell(
      onTap: usable ? onToggle : null,
      child: Opacity(
        opacity: usable ? 1 : 0.6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? colors.primary.withValues(alpha: 0.05) : null,
            border: Border(bottom: BorderSide(color: context.borderColor)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: usable
                      ? colors.primary.withValues(alpha: 0.1)
                      : Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(
                  coupon.type == CouponType.freeShipping
                      ? LucideIcons.truck
                      : LucideIcons.tag,
                  size: 16,
                  color: usable ? colors.primary : context.mutedForeground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      couponBenefitHeadline(coupon.type, coupon.value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    Text(
                      couponTermsLine(coupon.minPurchase),
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    const SizedBox(height: 2),
                    if (usable)
                      Text(
                        [
                          if (expiry != null) expiry.text,
                          'Sisa ${coupon.remainingUses}x',
                        ].join(' · '),
                        style: AppTypography.caption(
                          expiry?.urgent ?? false
                              ? context.appSemantic.gold
                              : context.mutedForeground,
                        ),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              LucideIcons.circleAlert,
                              size: 13,
                              color: context.mutedForeground,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              blockedReason ??
                                  couponIneligibleLabel(coupon, itemsSubtotal),
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (usable) ...[
                const SizedBox(width: 8),
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : null,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: selected ? colors.primary : context.borderColor,
                    ),
                  ),
                  child: selected
                      ? Icon(
                          LucideIcons.check,
                          size: 13,
                          color: colors.onPrimary,
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
