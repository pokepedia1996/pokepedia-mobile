import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../usecase/expansions_notifier.dart';

/// Ports `RelatedCardsSection` from
/// `features/card-detail/components/catalog/card-detail.tsx` — a horizontal
/// rail of the card's other prints, above a top rule.
///
/// The web pairs the rail with prev/next scroll buttons because a desktop
/// pointer has no other way to move it; on a phone the rail is swiped, so
/// the buttons are dropped rather than reproduced as dead ornaments.
class RelatedCardsSection extends ConsumerWidget {
  const RelatedCardsSection({super.key, required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      relatedCardsProvider((name: card.name, excludeId: card.id)),
    );
    final related = async.valueOrNull ?? const <CardModel>[];

    // Web renders nothing at all for an empty list, and a card with a single
    // print is the common case — so no heading and no empty state, and
    // nothing while the query is still in flight either.
    if (related.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Divider(color: context.borderColor, height: 1),
        const SizedBox(height: 20),
        Text(
          'Kartu Terkait',
          style: AppTypography.h3(context.appColors.onSurface),
        ),
        const SizedBox(height: 12),
        // A scrolling Row rather than a horizontal ListView: a ListView
        // needs its cross-axis extent given up front, and any height
        // computed here is a magic number that breaks the moment the
        // caption wraps or the reader scales their font up. The Row takes
        // its height from the tallest thumb instead. The query caps at 20
        // cards, so building them all is cheap — the web renders all 20 too.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              for (final related in related) _RelatedCardThumb(card: related),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ports `HoverCardThumb` — the 120px-wide thumbnail with the card name and
/// its expansion underneath.
class _RelatedCardThumb extends ConsumerWidget {
  const _RelatedCardThumb({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;

    // Web looks the set symbol up in a `symbols` map it fetches for every
    // expansion; the same lookup comes free off `seriesGroupsProvider`,
    // which the expansions tab has usually loaded already. Matched on code
    // *and* language, since each language has its own expansion row.
    final symbolUrl = ref
        .watch(seriesGroupsProvider)
        .valueOrNull
        ?.expand((group) => group.packs)
        .where(
          (pack) =>
              pack.slug == card.expansionCode.toLowerCase() &&
              pack.language == card.language.raw,
        )
        .map((pack) => pack.setSymbolUrl)
        .firstOrNull;

    return SizedBox(
      width: 120,
      child: InkWell(
        onTap: () => context.push(Routes.cardDetail(card.packSlug, card.id)),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardArt(imageUrl: card.imageUrl, borderRadius: AppRadius.md),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionSemibold(colors.onSurface),
                    ),
                    const SizedBox(height: 2),
                    // The symbol image when there is one, else the
                    // expansion code — web's own fallback.
                    if (symbolUrl != null)
                      Image.network(
                        symbolUrl,
                        height: 16,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        errorBuilder: (context, _, __) =>
                            _CodeLabel(card: card),
                      )
                    else
                      _CodeLabel(card: card),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeLabel extends StatelessWidget {
  const _CodeLabel({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Text(
        card.expansionCode.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption(context.mutedForeground),
      ),
    );
  }
}
