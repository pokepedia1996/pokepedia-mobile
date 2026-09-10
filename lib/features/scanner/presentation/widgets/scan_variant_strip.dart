import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../repository/models/scan_models.dart';
import 'scan_card_thumb.dart';

/// Ports `ScanVariantStrip` — the reprint/finish picker.
///
/// This is the correction path the whole feature leans on. Recognition doesn't
/// have to be right first time, because the embedding reliably identifies the
/// *artwork* while being structurally unable to separate reprints of it: the
/// only difference between a card's SVK and SVM printings is small printed
/// text that a coarse image embedding was never going to resolve. So the
/// scanner shows its best guess and puts every same-artwork sibling one tap
/// away, rather than trying to be certain.
///
/// The trailing search tile is the escape hatch for the other failure mode —
/// wrong card entirely, not just wrong printing.
class ScanVariantStrip extends StatelessWidget {
  const ScanVariantStrip({
    super.key,
    required this.selected,
    required this.variants,
    required this.onSelect,
    required this.onSearch,
  });

  final ScanCard selected;
  final List<ScanCard> variants;
  final ValueChanged<ScanCard> onSelect;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: variants.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == variants.length) {
            return _SearchTile(onTap: onSearch);
          }
          final card = variants[index];
          return _VariantTile(
            card: card,
            selected: card.id == selected.id,
            onTap: () => onSelect(card),
          );
        },
      ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({
    required this.card,
    required this.selected,
    required this.onTap,
  });

  final ScanCard card;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? colors.primary : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScanCardThumb(card: card, width: 56),
            const SizedBox(height: 3),
            Text(
              // The set code is what actually distinguishes one reprint from
              // another, so it — not the name, which is identical across the
              // whole strip — is the label.
              card.expansionCode ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.badge(
                selected ? colors.onSurface : context.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: context.borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.search, size: 22, color: context.mutedForeground),
            const SizedBox(height: 4),
            Text(
              'Ganti\nkartu',
              textAlign: TextAlign.center,
              style: AppTypography.badge(context.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
