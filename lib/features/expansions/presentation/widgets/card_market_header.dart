import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/card_ownership_controller.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';
import '../../../portfolio/usecase/portfolio_notifier.dart';
import '../../repository/models/market_models.dart';
import '../../usecase/expansions_notifier.dart';
import 'order_book_widget.dart';

/// Ports `features/card-detail/components/market/card-mobile-header.tsx` —
/// the card's name and wishlist toggle over the headline price: the latest
/// traded price with its 7-day move, falling back to the cached
/// listing/bid-derived price when the card has never sold.
class CardMarketHeader extends ConsumerWidget {
  const CardMarketHeader({super.key, required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headlineAsync = ref.watch(marketHeadlineProvider(card.id));
    final fallbackAsync = ref.watch(cardMarketPriceProvider(card.id));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (headlineAsync.isLoading || fallbackAsync.isLoading)
                const _HeadlinePlaceholder()
              else
                _Headline(
                  headline: headlineAsync.valueOrNull,
                  fallback: fallbackAsync.valueOrNull,
                ),
              const SizedBox(width: 8),
              WishlistButton(cardId: card.id),
            ],
          ),
          // Inside the same box as the price: bidding or asking is a
          // response to that number, not a separate piece of furniture.
          PlaceOrderButtons(card: card),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.headline, required this.fallback});

  final MarketHeadline? headline;
  final CardMarketPrice? fallback;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final headline = this.headline;
    final fallback = this.fallback;

    if (headline != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Harga ${headline.condition.short} terkini · $headlineDays hari',
            style: AppTypography.caption(context.mutedForeground),
          ),
          const SizedBox(height: 2),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                formatRupiah(headline.price),
                style: AppTypography.h2(colors.onSurface),
              ),
              if (headline.delta != 0)
                PriceDeltaPill(
                  delta: headline.delta,
                  deltaPct: headline.deltaPct,
                ),
            ],
          ),
        ],
      );
    }

    if (fallback != null) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            formatRupiah(fallback.price),
            style: AppTypography.h2(colors.onSurface),
          ),
          if (fallback.source == CardPriceSource.ask)
            _SourceTag(
              label: 'Listing termurah',
              color: context.mutedForeground,
            ),
          if (fallback.source == CardPriceSource.bid)
            _SourceTag(
              label: 'Penawaran tertinggi',
              color: context.appSemantic.gold,
            ),
        ],
      );
    }

    return Text(
      'Belum ada data harga',
      style: AppTypography.caption(context.mutedForeground),
    );
  }
}

/// The green/red "↑ Rp5.000 (4,0%)" chip web puts next to a headline price.
class PriceDeltaPill extends StatelessWidget {
  const PriceDeltaPill({
    super.key,
    required this.delta,
    required this.deltaPct,
  });

  final int delta;
  final double deltaPct;

  @override
  Widget build(BuildContext context) {
    final positive = delta >= 0;
    final color = positive
        ? context.appSemantic.success
        : context.appColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        '${positive ? '↑' : '↓'} ${formatRupiah(delta.abs())} '
        '(${deltaPct.abs().toStringAsFixed(1)}%)',
        style: AppTypography.captionSemibold(color),
      ),
    );
  }
}

class _SourceTag extends StatelessWidget {
  const _SourceTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(label, style: AppTypography.caption(color)),
    );
  }
}

class _HeadlinePlaceholder extends StatelessWidget {
  const _HeadlinePlaceholder();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.appColors.secondary,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bar(120, 12), const SizedBox(height: 8), bar(160, 24)],
    );
  }
}

/// Ports `components/catalog/wishlist-button.tsx` in its `display="label"`
/// form — the heart + "Wishlist" pill shown next to the card's name.
class WishlistButton extends ConsumerStatefulWidget {
  const WishlistButton({super.key, required this.cardId});

  final int cardId;

  @override
  ConsumerState<WishlistButton> createState() => _WishlistButtonState();
}

class _WishlistButtonState extends ConsumerState<WishlistButton> {
  bool _toggling = false;

  Future<void> _toggle(bool wishlisted) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      context.push(Routes.login);
      return;
    }
    setState(() => _toggling = true);
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .setWishlisted(widget.cardId, !wishlisted);
    if (!mounted) return;
    setState(() => _toggling = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wishlisted = ref.watch(isWishlistedProvider(widget.cardId));
    final color = wishlisted
        ? context.appColors.primary
        : context.mutedForeground;

    return InkWell(
      onTap: _toggling ? null : () => _toggle(wishlisted),
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: wishlisted
                ? color.withValues(alpha: 0.4)
                : context.borderColor,
          ),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_toggling)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(
                wishlisted ? LucideIcons.heart : LucideIcons.heart,
                size: 14,
                color: color,
              ),
          ],
        ),
      ),
    );
  }
}
