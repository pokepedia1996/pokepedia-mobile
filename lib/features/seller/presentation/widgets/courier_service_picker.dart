import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/widgets/coretan_kit.dart';
import '../../../../shared/widgets/setup_kit.dart';
import '../seller_couriers_page.dart';

/// The courier services a store takes, ticked by hand: a count over the
/// lot, then a card per speed — Instan, Same Day, Overnight, Reguler — each
/// with its own "Pilih semua".
///
/// Buka Toko's "Atur manual" step and the store's Kurir settings are this
/// same list, so a seller changing their couriers later sees what they
/// picked them from.
class CourierServicePicker extends StatelessWidget {
  const CourierServicePicker({
    super.key,
    required this.catalog,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.tickIn = false,
  });

  final Map<CourierBucket, List<CourierService>> catalog;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  /// Draw the boxes that start ticked one after another, as the screen
  /// arrives — 420 ms, then 40 ms a row, for the first 14.
  final bool tickIn;

  @override
  Widget build(BuildContext context) {
    final allIds = [
      for (final services in catalog.values)
        for (final s in services) s.id,
    ];
    final all = selected.length == allIds.length;
    final palette = DesignPalette.of(context);
    final buckets = [
      for (final b in CourierBucket.values)
        if ((catalog[b] ?? const []).isNotEmpty) b,
    ];
    // Where each card's rows start in the list as a whole, for the
    // tick-in delays.
    final firstRows = <CourierBucket, int>{};
    var rows = 0;
    for (final b in buckets) {
      firstRows[b] = rows;
      rows += catalog[b]!.length;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: CoretanPop(
                  value: selected.length,
                  child: Text(
                    '${selected.length} dari ${allIds.length} layanan dipilih',
                    style: AppTypography.hand(palette.brand, size: 18),
                  ),
                ),
              ),
            ),
            _Link(
              label: all ? 'Kosongkan' : 'Pilih semua',
              onTap: enabled
                  ? () => onChanged(all ? <String>{} : allIds.toSet())
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        // The cards are white paper on any page, so they read the light
        // palette even in a dark app.
        Theme(
          data: AppTheme.light,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final bucket in buckets) ...[
                _BucketCard(
                  bucket: bucket,
                  services: catalog[bucket]!,
                  selected: selected,
                  enabled: enabled,
                  firstRow: firstRows[bucket]!,
                  tickIn: tickIn,
                  onChanged: onChanged,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// How each speed is marked: a Lucide icon on a tinted disc.
(IconData, Color disc, Color ink) _bucketLook(CourierBucket bucket) =>
    switch (bucket) {
      CourierBucket.instant => (
        LucideIcons.zap,
        const Color(0xFFFDF1D8),
        const Color(0xFF8A5A00),
      ),
      CourierBucket.sameDay => (
        LucideIcons.sun,
        const Color(0xFFFBEDEB),
        const Color(0xFFAC403A),
      ),
      CourierBucket.overnight => (
        LucideIcons.moon,
        const Color(0xFFE8EEFB),
        const Color(0xFF2F5AA8),
      ),
      CourierBucket.reguler => (
        LucideIcons.truck,
        const Color(0xFFE3F6EA),
        const Color(0xFF1F7A44),
      ),
    };

class _BucketCard extends StatelessWidget {
  const _BucketCard({
    required this.bucket,
    required this.services,
    required this.selected,
    required this.enabled,
    required this.firstRow,
    required this.tickIn,
    required this.onChanged,
  });

  final CourierBucket bucket;
  final List<CourierService> services;
  final Set<String> selected;
  final bool enabled;

  /// The index of this card's first row across the whole list.
  final int firstRow;
  final bool tickIn;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final ids = [for (final s in services) s.id];
    final on = ids.where(selected.contains).length;
    final allOn = on == ids.length;
    final (icon, disc, ink) = _bucketLook(bucket);
    final first = firstRow;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.onbLine, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            color: const Color(0xFFFBF8F1),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: disc,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: ink),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    bucket.label,
                    style: setupText(16, palette.ink, FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$on/${ids.length}',
                  style: AppTypography.hand(palette.muted, size: 17),
                ),
                const Spacer(),
                _Link(
                  label: allOn ? 'Hapus semua' : 'Pilih semua',
                  onTap: enabled
                      ? () => onChanged(
                          allOn
                              ? ({...selected}..removeAll(ids))
                              : {...selected, ...ids},
                        )
                      : null,
                ),
              ],
            ),
          ),
          for (var i = 0; i < services.length; i++) ...[
            const Divider(height: 1, thickness: 1, color: AppColors.onbLine),
            _ServiceRow(
              service: services[i],
              checked: selected.contains(services[i].id),
              tickDelay: tickIn && first + i < 14
                  ? Duration(milliseconds: 420 + 40 * (first + i))
                  : Duration.zero,
              onTap: enabled
                  ? () {
                      final next = {...selected};
                      if (!next.remove(services[i].id)) {
                        next.add(services[i].id);
                      }
                      onChanged(next);
                    }
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.checked,
    required this.tickDelay,
    required this.onTap,
  });

  final CourierService service;
  final bool checked;
  final Duration tickDelay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Semantics(
      checked: checked,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              children: [
                CoretanCheckbox(checked: checked, delay: tickDelay),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: service.courierName,
                              style: setupText(
                                16.5,
                                palette.ink,
                                FontWeight.w800,
                              ),
                            ),
                            TextSpan(
                              text: ' · ${service.serviceName}',
                              style: setupText(
                                16.5,
                                palette.muted,
                                FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (service.duration.isNotEmpty)
                        Text(
                          service.duration,
                          style: setupText(14, palette.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Pilih semua", "Hapus semua": a word in red bold that does something.
class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: palette.brand,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: setupText(15, palette.brand, FontWeight.w700)),
    );
  }
}
