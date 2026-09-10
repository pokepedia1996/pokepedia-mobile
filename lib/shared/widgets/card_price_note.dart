import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/card_market_price.dart';
import '../models/card_model.dart';

/// What sits beside a card's price on a catalog tile: the week's move when
/// there is one, otherwise where the price came from.
///
/// Ports the rest of `priceBlock` in `components/card/card-item.tsx`. The two
/// are alternatives rather than a pair — `card_market_price_cache` only fills
/// `price_7d_ago` on its confirmed rows, so a price that came off the order
/// book can never have a move to show, and a confirmed one that can is past
/// needing to say where it came from.
///
/// This matters more than it looks: almost every card in the catalog is
/// priced from the cheapest open listing rather than from sales. Without the
/// badge those tiles state a number with nothing to say it is one seller's
/// asking price rather than what the card trades at.
class CardPriceNote extends StatelessWidget {
  const CardPriceNote({super.key, required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
    if (content == null) return const SizedBox.shrink();

    // Scaled down rather than truncated when the row is tight — a two-up
    // grid on a 360pt phone has no room for "Qty: 3", a seven-figure price
    // and this all at full size, and a clipped "↑38…" reads as broken where
    // a slightly smaller one just reads. The Flexible the caller wraps this
    // in is what bounds the scaling; the gap is in here so that a tile with
    // nothing to add doesn't leave one hanging off its price.
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: content,
      ),
    );
  }

  Widget? _content(BuildContext context) {
    final pct = card.priceChangePct;
    if (pct != null) return _Trend(pct: pct);

    return switch (card.priceSource) {
      // Web writes these "Listing termurah" and "Penawaran tertinggi". A
      // grid cell is ~150pt wide with a price already in it, so the noun is
      // dropped and the superlative — the half that says which end of the
      // book the number is from — is kept. The card detail page has the room
      // for the full wording and still uses it.
      CardPriceSource.ask => _SourceBadge(
        label: 'Termurah',
        color: context.mutedForeground,
      ),
      CardPriceSource.bid => _SourceBadge(
        label: 'Tertinggi',
        color: context.appSemantic.gold,
      ),
      // Priced from real sales, but with no week behind it yet.
      CardPriceSource.confirmed => _SourceBadge(
        label: 'Baru',
        color: context.mutedForeground.withValues(alpha: 0.7),
      ),
      null => null,
    };
  }
}

/// "↑100.0% · 7H" — web's `pricePct` span.
class _Trend extends StatelessWidget {
  const _Trend({required this.pct});

  final double pct;

  @override
  Widget build(BuildContext context) {
    final arrow = pct > 0
        ? '↑'
        : pct < 0
        ? '↓'
        : '';
    final muted = context.mutedForeground;
    final tone = pct > 0
        ? context.appSemantic.success
        : pct < 0
        ? context.appColors.error
        : muted;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$arrow${pct.abs().toStringAsFixed(1)}%',
            style: AppTypography.captionSemibold(tone),
          ),
          // The window the move is measured over, in the same shorthand the
          // portfolio chart's range chips use.
          TextSpan(
            text: ' · 7H',
            style: AppTypography.caption(muted.withValues(alpha: 0.7)),
          ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// The outlined chip web draws around a price's provenance, matching the one
/// `card_market_header` puts beside the headline price.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: AppTypography.caption(color),
      ),
    );
  }
}
