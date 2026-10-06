import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/models/scan_models.dart';
import '../../usecase/scan_session_notifier.dart';
import 'scan_card_search_sheet.dart';
import 'scan_card_thumb.dart';
import 'scan_variant_strip.dart';

/// Ports `ScanResultSheet` — the bottom dock, drawn straight over the camera
/// preview the way web draws it: the card just recognized on the left (price,
/// name, printing, thumb), the running total and the way into the batch on
/// the right.
///
/// No sheet behind it. The preview stays the whole screen, and the dock
/// slides in only once the session has something in it — before the first
/// scan there is nothing to show and nothing to manage.
class ScanResultSheet extends ConsumerStatefulWidget {
  const ScanResultSheet({
    super.key,
    required this.item,
    required this.onSelectVariant,
    required this.onOpenSession,
  });

  /// The most recent scan's session row, or null before the first result.
  final ScanSessionItem? item;

  final ValueChanged<ScanCard> onSelectVariant;
  final VoidCallback onOpenSession;

  @override
  ConsumerState<ScanResultSheet> createState() => _ScanResultSheetState();
}

class _ScanResultSheetState extends ConsumerState<ScanResultSheet> {
  var _stripExpanded = false;

  @override
  void didUpdateWidget(ScanResultSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A freshly landed capture must never inherit a still-expanded strip left
    // over from the card it replaced.
    if (oldWidget.item?.tempId != widget.item?.tempId && _stripExpanded) {
      _stripExpanded = false;
    }
  }

  Future<void> _openSearch(ScanSessionItem item) async {
    final picked = await showModalBottomSheet<ScanCard>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // The sheet's own context, not this widget's — popping the outer one
      // would dismiss the scanner instead of the search sheet.
      builder: (sheetContext) => ScanCardSearchSheet(
        language: item.card.language,
        onSelect: (card) => Navigator.of(sheetContext).pop(card),
      ),
    );
    if (picked != null && mounted) {
      widget.onSelectVariant(picked);
      setState(() => _stripExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final session = ref.watch(scanSessionProvider);
    final prices = ref.watch(scanSessionPricesProvider).valueOrNull;
    final total = session.fold<int>(
      0,
      (sum, it) => sum + (prices?[it.card.id]?.price ?? 0) * it.quantity,
    );
    final quantity = session.fold<int>(0, (sum, it) => sum + it.quantity);
    final open = session.isNotEmpty;
    final padding = MediaQuery.of(context).padding;

    final Widget content;
    if (item != null && _stripExpanded) {
      content = ScanVariantStrip(
        selected: item.card,
        variants: item.variants.isNotEmpty ? item.variants : [item.card],
        onSelect: (card) {
          widget.onSelectVariant(card);
          setState(() => _stripExpanded = false);
        },
        onSearch: () => _openSearch(item),
        dark: true,
      );
    } else {
      content = Padding(
        padding: EdgeInsets.only(
          left: padding.left + 16,
          right: padding.right + 16,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: item == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.bottomLeft,
                      child: _CardPreview(
                        // Keyed on the row so each new match animates in,
                        // not just the first — web's `card?.id` dependency.
                        key: ValueKey(item.tempId),
                        item: item,
                        price: prices?[item.card.id]?.price,
                        onTap: () => setState(() => _stripExpanded = true),
                      ),
                    ),
            ),
            // Web's 5.5rem middle column, kept clear of the preview.
            const SizedBox(width: 88),
            Expanded(
              child: open
                  ? _TotalColumn(
                      total: total,
                      quantity: quantity,
                      onOpenSession: widget.onOpenSession,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedSlide(
          offset: open ? Offset.zero : const Offset(0, 1),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: Padding(
            padding: EdgeInsets.only(top: 16, bottom: padding.bottom + 24),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _CardPreview extends StatelessWidget {
  const _CardPreview({
    super.key,
    required this.item,
    required this.price,
    required this.onTap,
  });

  final ScanSessionItem item;
  final int? price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = item.card;
    final price = this.price;
    // Web's entrance: up 20px from 96% scale, `power3.out`.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - t)),
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
      ),
      child: Semantics(
        button: true,
        label: 'Ganti varian atau kartu',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (price != null)
                Text(
                  formatRupiah(price),
                  style: AppTypography.bodySm(
                    Colors.white,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      card.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmSemibold(Colors.white),
                    ),
                  ),
                  // Not on web. Kept because it tells the user which rows to
                  // check before committing the batch, so an unconfident
                  // guess is never mistaken for a settled answer.
                  if (item.needsReview) ...[
                    const SizedBox(width: 6),
                    const _ReviewBadge(),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  card.printingLabel,
                  if (card.variantLabel != null) card.variantLabel!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(Colors.white70),
              ),
              const SizedBox(height: 4),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ScanCardThumb(card: card, width: 80),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.pencil,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalColumn extends StatelessWidget {
  const _TotalColumn({
    required this.total,
    required this.quantity,
    required this.onOpenSession,
  });

  final int total;
  final int quantity;
  final VoidCallback onOpenSession;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Total', style: AppTypography.caption(Colors.white60)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            formatRupiah(total),
            style: AppTypography.h3(
              Colors.white,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: 'Kelola kartu',
          excludeSemantics: true,
          child: FilledButton(
            onPressed: onOpenSession,
            style: FilledButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Kelola ($quantity)',
              style: AppTypography.captionSemibold(colors.onPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewBadge extends StatelessWidget {
  const _ReviewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: context.appSemantic.gold.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('Cek', style: AppTypography.badge(context.appSemantic.gold)),
    );
  }
}
