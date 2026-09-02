import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/models/checkout_models.dart';

/// Ports `features/checkout/ui/CourierPicker.tsx` — a trigger button that
/// opens a bottom sheet listing shipping quotes bucketed by speed.
class CourierPicker extends StatelessWidget {
  const CourierPicker({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<CourierOption> options;
  final CourierOption? selected;
  final ValueChanged<CourierOption> onSelect;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<CourierOption>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _CourierPickerSheet(options: options, selected: selected),
    );
    if (picked != null) onSelect(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = selected;
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: s != null
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
                color: s != null
                    ? colors.primary.withValues(alpha: 0.1)
                    : Theme.of(context).colorScheme.secondary,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(
                s != null ? _bucketIcon(s.bucket) : LucideIcons.truck,
                size: 16,
                color: s != null ? colors.primary : context.mutedForeground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s != null
                        ? '${s.courierName} ${s.description}'
                        : 'Pilih pengiriman',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  Text(
                    s != null
                        ? '${_bucketMeta(s.bucket).title} · Estimasi tiba ${s.etaLabel}'
                        : '${options.length} layanan tersedia',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            if (s != null) ...[
              Text(
                formatRupiah(s.cost),
                style: AppTypography.bodySmSemibold(colors.primary),
              ),
              const SizedBox(width: 4),
            ],
            Icon(
              LucideIcons.chevronDown,
              size: 18,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

IconData _bucketIcon(CourierBucket bucket) =>
    courierBucketMetas.firstWhere((m) => m.bucket == bucket).icon;

CourierBucketMeta _bucketMeta(CourierBucket bucket) =>
    courierBucketMetas.firstWhere((m) => m.bucket == bucket);

class _CourierPickerSheet extends StatelessWidget {
  const _CourierPickerSheet({required this.options, required this.selected});

  final List<CourierOption> options;
  final CourierOption? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final byBucket = <CourierBucket, List<CourierOption>>{
      for (final m in courierBucketMetas) m.bucket: [],
    };
    for (final opt in options) {
      byBucket[opt.bucket]!.add(opt);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pilih pengiriman',
                  style: AppTypography.h3(colors.onSurface),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  for (final meta in courierBucketMetas)
                    if (byBucket[meta.bucket]!.isNotEmpty)
                      _BucketSection(
                        meta: meta,
                        options: byBucket[meta.bucket]!,
                        selected: selected,
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

class _BucketSection extends StatelessWidget {
  const _BucketSection({
    required this.meta,
    required this.options,
    required this.selected,
  });

  final CourierBucketMeta meta;
  final List<CourierOption> options;
  final CourierOption? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4),
          child: Row(
            children: [
              Icon(meta.icon, size: 14, color: context.mutedForeground),
              const SizedBox(width: 6),
              Text(
                meta.title,
                style: AppTypography.captionSemibold(context.mutedForeground),
              ),
              Text(
                ' · ${meta.caption}',
                style: AppTypography.caption(
                  context.mutedForeground.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        for (final opt in options)
          InkWell(
            onTap: () => Navigator.of(context).pop(opt),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: selected?.optionKey == opt.optionKey
                    ? colors.primary.withValues(alpha: 0.05)
                    : null,
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${opt.courierName} ${opt.description}',
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        Text(
                          'Estimasi tiba ${opt.etaLabel}',
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatRupiah(opt.cost),
                    style: AppTypography.bodySmSemibold(colors.primary),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected?.optionKey == opt.optionKey
                          ? colors.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: selected?.optionKey == opt.optionKey
                            ? colors.primary
                            : context.borderColor,
                      ),
                    ),
                    child: selected?.optionKey == opt.optionKey
                        ? Icon(
                            LucideIcons.check,
                            size: 13,
                            color: colors.onPrimary,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
