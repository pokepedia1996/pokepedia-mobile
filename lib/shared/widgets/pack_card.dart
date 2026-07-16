import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/pack_model.dart';
import 'pokeball_icon.dart';

/// Ports `components/pack/pack-card.tsx` — a grid tile for an expansion with
/// its collected/total progress bar.
class PackCard extends StatelessWidget {
  const PackCard({super.key, required this.pack, required this.onTap});

  final PackModel pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final percent = (pack.progress * 100).round();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Center(
                  child: Text(
                    pack.name.substring(0, 1),
                    style: AppTypography.h1(
                      context.mutedForeground.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                PokeballIcon(size: 16, color: colors.primary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    pack.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'Dirilis: ${pack.releaseDate}',
              style: AppTypography.caption(context.mutedForeground),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${pack.collectedCount}/${pack.cardCount}',
                  style: AppTypography.captionSemibold(
                    colors.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  '$percent%',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: pack.progress.clamp(0, 1),
                minHeight: 6,
                backgroundColor: colors.secondary,
                valueColor: AlwaysStoppedAnimation(colors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
