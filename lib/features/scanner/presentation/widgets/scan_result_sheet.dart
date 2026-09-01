import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/card_language_badge.dart';
import '../../repository/models/scan_models.dart';
import '../../usecase/scan_session_notifier.dart';
import 'scan_card_search_sheet.dart';
import 'scan_card_thumb.dart';
import 'scan_variant_strip.dart';

/// Ports `ScanResultSheet` — the bottom dock: the shutter, the card just
/// recognized with its price, and the way into the batch.
///
/// It stays mounted with the shutter visible even before the first scan, so
/// the primary control never moves. The card summary expands in above it once
/// there's a result.
class ScanResultSheet extends ConsumerStatefulWidget {
  const ScanResultSheet({
    super.key,
    required this.item,
    required this.sessionCount,
    required this.busy,
    required this.onCapture,
    required this.onSelectVariant,
    required this.onOpenSession,
  });

  /// The most recent scan's session row, or null before the first result.
  final ScanSessionItem? item;

  final int sessionCount;
  final bool busy;
  final VoidCallback onCapture;
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
    final prices = ref.watch(scanSessionPricesProvider).valueOrNull;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: context.appColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 12,
          top: 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item != null) ...[
              _ResultRow(
                item: item,
                price: prices?[item.card.id]?.price,
                expanded: _stripExpanded,
                onToggleStrip: () =>
                    setState(() => _stripExpanded = !_stripExpanded),
              ),
              if (_stripExpanded) ...[
                const SizedBox(height: 8),
                ScanVariantStrip(
                  selected: item.card,
                  variants: item.variants.isNotEmpty
                      ? item.variants
                      : [item.card],
                  onSelect: (card) {
                    widget.onSelectVariant(card);
                    setState(() => _stripExpanded = false);
                  },
                  onSearch: () => _openSearch(item),
                ),
              ],
              const SizedBox(height: 12),
            ],
            _ShutterRow(
              busy: widget.busy,
              sessionCount: widget.sessionCount,
              onCapture: widget.onCapture,
              onOpenSession: widget.onOpenSession,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.item,
    required this.price,
    required this.expanded,
    required this.onToggleStrip,
  });

  final ScanSessionItem item;
  final int? price;
  final bool expanded;
  final VoidCallback onToggleStrip;

  @override
  Widget build(BuildContext context) {
    final card = item.card;
    final language = card.language;
    return InkWell(
      onTap: onToggleStrip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            ScanCardThumb(card: card, width: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (language != null) ...[
                        CardLanguageBadge(language: language, size: 14),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          card.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(
                            context.appColors.onSurface,
                          ),
                        ),
                      ),
                      // The badge is the whole point of tracking confidence:
                      // it tells the user which rows to look at before
                      // committing the batch, so an unconfident guess is
                      // never mistaken for a settled answer.
                      if (item.needsReview) ...[
                        const SizedBox(width: 6),
                        const _ReviewBadge(),
                      ],
                      Icon(
                        expanded ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                        color: context.mutedForeground,
                      ),
                    ],
                  ),
                  Text(
                    [
                      card.printingLabel,
                      if (card.variantLabel != null) card.variantLabel!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              // A dash rather than a zero while the price is still in flight —
              // the price fetch is deliberately off the scan's critical path,
              // so this gap is normal and must not read as "worthless".
              price == null ? 'Rp-' : formatRupiah(price!),
              style: AppTypography.bodySemibold(context.appColors.onSurface),
            ),
          ],
        ),
      ),
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

class _ShutterRow extends StatelessWidget {
  const _ShutterRow({
    required this.busy,
    required this.sessionCount,
    required this.onCapture,
    required this.onOpenSession,
  });

  final bool busy;
  final int sessionCount;
  final VoidCallback onCapture;
  final VoidCallback onOpenSession;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Balances the batch button so the shutter stays centred.
          const SizedBox(width: 76),
          Expanded(
            child: Center(
              child: Semantics(
                button: true,
                label: 'Pindai kartu',
                child: GestureDetector(
                  onTap: busy ? null : onCapture,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: busy
                          ? context.borderColor
                          : context.appColors.primary,
                      border: Border.all(
                        color: context.appColors.surface,
                        width: 4,
                      ),
                    ),
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.center_focus_strong,
                            color: context.appColors.onPrimary,
                            size: 30,
                          ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 76,
            child: Align(
              alignment: Alignment.centerRight,
              child: Badge(
                isLabelVisible: sessionCount > 0,
                label: Text('$sessionCount'),
                child: IconButton(
                  onPressed: onOpenSession,
                  tooltip: 'Kelola kartu',
                  icon: const Icon(Icons.inventory_2_outlined),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
