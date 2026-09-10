import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/models/listing_model.dart';
import '../../../../shared/widgets/condition_badge.dart';
import '../../../../shared/widgets/condition_grade_picker.dart';
import '../../repository/models/market_models.dart';
import '../../usecase/expansions_notifier.dart';
import '../../utils/untradeable_expansions.dart';
import '../../../proposals/presentation/widgets/bid_edit_sheet.dart';
import '../../../proposals/presentation/widgets/make_offer_sheet.dart';
import '../../../proposals/usecase/proposals_notifier.dart';
import 'ask_seller_picker.dart';
import 'bid_proposal_sheet.dart';
import 'place_order_sheet.dart';

/// The deepest 10 levels per side, as web's `MAX_ROWS`.
const _maxRows = 10;

/// Ports `features/card-detail/components/market/order-book-widget.tsx` —
/// the aggregated bid/ask ladder with a condition filter, depth bars, the
/// per-side totals and the spread, plus the two buttons that write to it.
class OrderBookWidget extends ConsumerStatefulWidget {
  const OrderBookWidget({super.key, required this.card});

  /// The full card (not just its id) because the place-order sheet shows
  /// the card's name and number in its header.
  final CardModel card;

  @override
  ConsumerState<OrderBookWidget> createState() => _OrderBookWidgetState();
}

class _OrderBookWidgetState extends ConsumerState<OrderBookWidget> {
  CardCondition? _condition;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bookAsync = ref.watch(
      orderBookProvider((cardId: widget.card.id, condition: _condition)),
    );
    final book = bookAsync.valueOrNull;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Order Book',
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                    ),
                    if (book != null && book.activeMatchCount > 0)
                      Text(
                        '${book.activeMatchCount} transaksi berlangsung',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ConditionGradePicker(
                  value: _condition,
                  onChanged: (value) => setState(() => _condition = value),
                ),
              ],
            ),
          ),
          if (bookAsync.isLoading)
            const _LadderPlaceholder()
          else if (book == null || book.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: DottedEmptyBox(
                message: _condition == null
                    ? 'Belum ada order untuk kartu ini'
                    : 'Belum ada order dengan kondisi ini',
              ),
            )
          else
            _Ladder(book: book, card: widget.card),
        ],
      ),
    );
  }
}

/// "Pasang Bid (WTB)" / "Pasang Ask (WTS)" — the two ways onto the book.
///
/// Lives beside the price rather than at the foot of the ladder: the price
/// is what someone is reacting to when they decide to bid or ask.
class PlaceOrderButtons extends ConsumerWidget {
  const PlaceOrderButtons({super.key, required this.card});

  final CardModel card;

  Future<void> _place(
    BuildContext context,
    WidgetRef ref,
    String side,
    int? bestPrice,
  ) async {
    final placed = await showPlaceOrderSheet(
      context,
      card: card,
      side: side,
      bestPrice: bestPrice,
    );
    if (placed == true) {
      // Family-wide: the ladder below may be filtered to one grade, and
      // this doesn't know which.
      ref.invalidate(orderBookProvider);
      ref.invalidate(cardListingsProvider(card.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isUntradeableExpansion(card.expansionCode)) {
      return Text(
        'Kartu ini belum bisa diperdagangkan.',
        textAlign: TextAlign.center,
        style: AppTypography.caption(context.mutedForeground),
      );
    }

    // The unfiltered book, purely to prefill the form — the sheet asks for
    // a condition itself.
    final book = ref
        .watch(orderBookProvider((cardId: card.id, condition: null)))
        .valueOrNull;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => _place(context, ref, 'bid', book?.bestBid),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.appSemantic.success,
              minimumSize: const Size(0, 40),
            ),
            child: const Text('Pasang Bid (WTB)'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _place(context, ref, 'ask', book?.bestAsk),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.appColors.error,
              minimumSize: const Size(0, 40),
            ),
            child: const Text('Pasang Ask (WTS)'),
          ),
        ),
      ],
    );
  }
}

class _Ladder extends StatelessWidget {
  const _Ladder({required this.book, required this.card});

  final OrderBookData book;
  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final semantic = context.appSemantic;
    final bids = book.bids.take(_maxRows).toList();
    final asks = book.asks.take(_maxRows).toList();
    final rowCount = bids.length > asks.length ? bids.length : asks.length;

    // Web pads the ask column at the *start* so the best ask sits closest to
    // the spread row at the bottom, and the bid column at the end.
    final askOffset = rowCount - asks.length;

    var maxBidQty = 1;
    for (final b in bids) {
      if (b.totalQuantity > maxBidQty) maxBidQty = b.totalQuantity;
    }
    var maxAskQty = 1;
    for (final a in asks) {
      if (a.totalQuantity > maxAskQty) maxAskQty = a.totalQuantity;
    }

    final totalBidQty = book.bids.fold<int>(0, (s, b) => s + b.totalQuantity);
    final totalAskQty = book.asks.fold<int>(0, (s, a) => s + a.totalQuantity);
    final spread = book.spread;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _HeadCell(label: 'Jml', align: TextAlign.right, flex: 12),
              _HeadCell(
                label: 'Bid',
                align: TextAlign.right,
                flex: 38,
                color: semantic.success,
              ),
              _HeadCell(
                label: 'Ask',
                align: TextAlign.left,
                flex: 38,
                color: context.appColors.error,
              ),
              _HeadCell(label: 'Jml', align: TextAlign.left, flex: 12),
            ],
          ),
        ),
        for (var i = 0; i < rowCount; i++)
          _LadderRow(
            card: card,
            bid: i < bids.length ? bids[i] : null,
            ask: i >= askOffset ? asks[i - askOffset] : null,
            maxBidQty: maxBidQty,
            maxAskQty: maxAskQty,
          ),
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.borderColor)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 12,
                child: Text(
                  '$totalBidQty',
                  style: AppTypography.captionSemibold(semantic.success),
                ),
              ),
              Expanded(
                flex: 38,
                child: Text(
                  'TOTAL',
                  textAlign: TextAlign.right,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
              Expanded(
                flex: 38,
                child: Text(
                  'TOTAL',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
              Expanded(
                flex: 12,
                child: Text(
                  '$totalAskQty',
                  textAlign: TextAlign.right,
                  style: AppTypography.captionSemibold(context.appColors.error),
                ),
              ),
            ],
          ),
        ),
        if (spread != null)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.appColors.secondary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text.rich(
              TextSpan(
                text: 'Spread: ',
                style: AppTypography.caption(context.mutedForeground),
                children: [
                  TextSpan(
                    text: formatRupiah(spread),
                    style: AppTypography.captionSemibold(
                      context.appColors.onSurface,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell({
    required this.label,
    required this.align,
    required this.flex,
    this.color,
  });

  final String label;
  final TextAlign align;
  final int flex;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          textAlign: align,
          style: AppTypography.caption(color ?? context.mutedForeground),
        ),
      ),
    );
  }
}

/// One price level per side.
///
/// Each half is independently tappable, the way web makes its bid cells
/// clickable: a bid opens the proposal that offers your card to everyone
/// standing at that price, an ask opens an offer to the sellers there.
class _LadderRow extends ConsumerWidget {
  const _LadderRow({
    required this.card,
    required this.bid,
    required this.ask,
    required this.maxBidQty,
    required this.maxAskQty,
  });

  final CardModel card;
  final OrderBookLevel? bid;
  final OrderBookLevel? ask;
  final int maxBidQty;
  final int maxAskQty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final semantic = context.appSemantic;
    final bid = this.bid;
    final ask = this.ask;

    return Container(
      color: bid?.viewerOwns == true
          ? semantic.bid.withValues(alpha: 0.08)
          : null,
      // 3px of padding around an 18px cell made a 24px row — under half a
      // finger, and two rows apart is a mis-tap. 8 around 24 lands at 40,
      // which is tappable without the ladder losing its density.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 12,
            child: _DepthCell(
              quantity: bid?.totalQuantity,
              fraction: bid == null ? 0 : bid.totalQuantity / maxBidQty,
              color: semantic.success,
              alignRight: true,
            ),
          ),
          Expanded(
            flex: 38,
            child: bid == null
                ? const SizedBox.shrink()
                : InkWell(
                    onTap: () => _onBidTap(context, ref, bid),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (bid.viewerOwns) ...[
                          _OwnBadge(color: semantic.bid),
                          const SizedBox(width: 4),
                        ],
                        ConditionBadge(condition: bid.condition, dense: true),
                        const SizedBox(width: 4),
                        Text(
                          formatRupiah(bid.price),
                          style: AppTypography.captionSemibold(
                            semantic.success,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Expanded(
            flex: 38,
            child: ask == null
                ? const SizedBox.shrink()
                : InkWell(
                    onTap: () => _onAskTap(context, ref, ask),
                    child: Row(
                      children: [
                        Text(
                          formatRupiah(ask.price),
                          style: AppTypography.captionSemibold(colors.error),
                        ),
                        const SizedBox(width: 4),
                        ConditionBadge(condition: ask.condition, dense: true),
                      ],
                    ),
                  ),
          ),
          Expanded(
            flex: 12,
            child: _DepthCell(
              quantity: ask?.totalQuantity,
              fraction: ask == null ? 0 : ask.totalQuantity / maxAskQty,
              color: colors.error,
              alignRight: false,
            ),
          ),
        ],
      ),
    );
  }

  /// Your own bid opens its editor; anyone else's opens the proposal.
  ///
  /// A level carries no listing slug, so an own bid is found back by price
  /// and condition — unambiguous because the wash guard allows only one open
  /// bid per card, variant and condition.
  Future<void> _onBidTap(
    BuildContext context,
    WidgetRef ref,
    OrderBookLevel level,
  ) async {
    if (level.viewerOwns) {
      await _editOwnBid(context, ref, level);
      return;
    }

    // Null, not `card.variant`: the ladder isn't variant-scoped, and every
    // order the app places leaves `variant_key` null too — filtering on
    // 'normal' would match none of them.
    final sent = await showBidProposalSheet(
      context,
      card: card,
      price: level.price,
      condition: level.condition,
    );
    if (sent == null || !context.mounted) return;

    ref.invalidate(orderBookProvider);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            sent == 1
                ? 'Proposal terkirim ke 1 pembeli!'
                : 'Proposal terkirim ke $sent pembeli!',
          ),
          persist: false,
        ),
      );
  }

  Future<void> _editOwnBid(
    BuildContext context,
    WidgetRef ref,
    OrderBookLevel level,
  ) async {
    final bids = await ref.read(myBidsProvider.future);
    final mine = bids
        .where(
          (b) =>
              b.card.id == card.id &&
              b.price == level.price &&
              b.condition == level.condition,
        )
        .firstOrNull;
    if (!context.mounted) return;

    if (mine == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Bid ini sudah berubah. Kelola di halaman Proposal.'),
            persist: false,
          ),
        );
      return;
    }

    final edit = await showBidEditSheet(context, bid: mine);
    if (edit == null || edit.isEmpty || !context.mounted) return;

    final error = await ref
        .read(proposalsRepositoryProvider)
        .updateBid(slug: mine.slug, price: edit.price, quantity: edit.quantity);
    if (!context.mounted) return;

    if (error == null) {
      ref.invalidate(orderBookProvider);
      ref.invalidate(myBidsProvider);
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(error ?? 'Bid diperbarui'), persist: false),
      );
  }

  /// An ask level can cover several sellers, so the offer needs one picked
  /// before it has a listing to negotiate against.
  Future<void> _onAskTap(
    BuildContext context,
    WidgetRef ref,
    OrderBookLevel level,
  ) async {
    final listings = await ref.read(cardListingsProvider(card.id).future);
    final matches = listings
        .where(
          (l) =>
              l.side == ListingSide.ask &&
              l.price == level.price &&
              l.condition == level.condition &&
              l.acceptsOffers,
        )
        .toList();
    if (!context.mounted) return;

    if (matches.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Penjual di harga ini tidak menerima penawaran.'),
            persist: false,
          ),
        );
      return;
    }

    final listing = matches.length == 1
        ? matches.first
        : await showAskSellerPicker(context, listings: matches);
    if (listing == null || !context.mounted) return;

    final made = await showMakeOfferSheet(context, listing: listing);
    if (made == true && context.mounted) {
      ref.invalidate(cardListingsProvider(card.id));
    }
  }
}

/// The height of a ladder row's quantity cell, which sets the row's own
/// height along with its padding.
const _depthCellHeight = 24.0;

/// A quantity cell whose background bar is scaled to the level's share of
/// the deepest level on that side (web's inline-width depth bars).
class _DepthCell extends StatelessWidget {
  const _DepthCell({
    required this.quantity,
    required this.fraction,
    required this.color,
    required this.alignRight,
  });

  final int? quantity;
  final double fraction;
  final Color color;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    if (quantity == null) return const SizedBox(height: _depthCellHeight);
    final alignment = alignRight ? Alignment.centerRight : Alignment.centerLeft;
    return SizedBox(
      height: _depthCellHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: alignment,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                heightFactor: 1,
                child: ColoredBox(color: color.withValues(alpha: 0.12)),
              ),
            ),
          ),
          Align(
            alignment: alignment,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '$quantity',
                style: AppTypography.caption(context.appColors.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnBadge extends StatelessWidget {
  const _OwnBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        'Kamu',
        style: AppTypography.badge(color).copyWith(fontSize: 9),
      ),
    );
  }
}

class _LadderPlaceholder extends StatelessWidget {
  const _LadderPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(
        children: [
          for (var i = 0; i < 6; i++)
            Container(
              height: 14,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: context.appColors.secondary,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
            ),
        ],
      ),
    );
  }
}

/// The dashed-border "nothing here yet" box web uses inside market panels.
class DottedEmptyBox extends StatelessWidget {
  const DottedEmptyBox({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: context.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodySm(context.mutedForeground),
      ),
    );
  }
}
