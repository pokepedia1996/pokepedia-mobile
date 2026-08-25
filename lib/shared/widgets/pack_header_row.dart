import 'package:flutter/material.dart';

import 'remote_image.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/routes.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/card_model.dart';
import '../models/pack_model.dart';

/// The expansion row above a card's artwork, ported from the header block of
/// `card-detail.tsx`: the pack image + name link back to the expansion on the
/// left, the set symbol and collector number sit on the right.
class PackHeaderRow extends StatelessWidget {
  const PackHeaderRow({super.key, required this.pack, required this.card});

  final PackModel? pack;
  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => context.push(Routes.packDetail(card.packSlug)),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: pack?.image != null
                      ? Image.network(
                          pack!.image!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _PackFallback(pack: pack),
                        )
                      : _PackFallback(pack: pack),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    pack?.name ?? card.expansionCode.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (pack?.setSymbolUrl != null)
          RemoteImage(
            url: pack!.setSymbolUrl!,
            height: 24,
          )
        else if (pack != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: context.borderColor),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              pack!.mark,
              style: AppTypography.caption(context.mutedForeground),
            ),
          ),
        const SizedBox(width: 6),
        Text(
          card.collectorNumber,
          style: AppTypography.caption(context.mutedForeground),
        ),
      ],
    );
  }
}

class _PackFallback extends StatelessWidget {
  const _PackFallback({required this.pack});

  final PackModel? pack;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Text(
        pack?.name.characters.firstOrNull ?? '?',
        style: AppTypography.bodySmSemibold(context.mutedForeground),
      ),
    );
  }
}
