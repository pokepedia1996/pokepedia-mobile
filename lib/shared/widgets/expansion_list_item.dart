import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/pack_model.dart';

/// Ports `features/expansions/components/expansion-list-item.tsx` — the row
/// an expansion takes in the list view: pack art in a muted tile, then the
/// set symbol, name, release date and card count.
class ExpansionListItem extends StatelessWidget {
  const ExpansionListItem({
    super.key,
    required this.pack,
    required this.onTap,
  });

  final PackModel pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: context.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 88,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              clipBehavior: Clip.antiAlias,
              child: pack.image == null
                  ? Text(
                      pack.name.characters.firstOrNull ?? '?',
                      style: AppTypography.h3(
                        context.mutedForeground.withValues(alpha: 0.5),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.network(
                        pack.image!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Text(
                          pack.name.characters.firstOrNull ?? '?',
                          style: AppTypography.h3(
                            context.mutedForeground.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SetSymbol(pack: pack),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          pack.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${pack.releaseDate} · ${pack.cardCount} kartu',
                    style: AppTypography.caption(context.mutedForeground),
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

/// The set symbol, falling back to the expansion code when the SVG is
/// missing or fails — same fallback the web row uses.
class _SetSymbol extends StatelessWidget {
  const _SetSymbol({required this.pack});

  final PackModel pack;

  @override
  Widget build(BuildContext context) {
    final mark = Text(
      pack.mark.toUpperCase(),
      style: AppTypography.overline(context.appColors.primary),
    );
    final url = pack.setSymbolUrl;
    if (url == null || url.isEmpty) return mark;

    return SvgPicture.network(
      url,
      height: 18,
      width: 18,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => mark,
    );
  }
}
