import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/pack_model.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  height: 180, // your fixed height
                  width: double.infinity, // fill the parent's width
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: pack.image == null
                      ? _PackInitial(pack: pack)
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Image.network(
                            pack.image!,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                ? child
                                : _PackInitial(pack: pack),
                            errorBuilder: (context, error, stackTrace) =>
                                _PackInitial(pack: pack),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                pack.setSymbolUrl != null
                    ? SvgPicture.network(
                        pack.setSymbolUrl!,
                        height: 15,
                        fit: BoxFit.contain,
                        placeholderBuilder: (context) => Text(
                          pack.mark,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        errorBuilder: (context, error, stackTrace) => Text(
                          pack.mark,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : Expanded(
                        child: Text(
                          pack.mark,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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

/// First-letter placeholder shown while [PackCard.pack.image] loads,
/// errors, or is absent (dummy data has no real art).
class _PackInitial extends StatelessWidget {
  const _PackInitial({required this.pack});

  final PackModel pack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        pack.name.isEmpty ? '?' : pack.name.substring(0, 1),
        style: AppTypography.h1(context.mutedForeground.withValues(alpha: 0.5)),
      ),
    );
  }
}
