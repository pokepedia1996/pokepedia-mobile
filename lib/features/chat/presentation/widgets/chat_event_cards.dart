import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../proposals/presentation/offers_page.dart';
import '../../../proposals/repository/models/listing_offer_model.dart';
import '../../../proposals/usecase/proposals_notifier.dart';
import '../../repository/models/chat_models.dart';

/// The system-authored bubbles, ported from `features/chat/components/events`.
///
/// Each is the same shape on the web: a labelled header strip with the time on
/// the right, the card it concerns, and a footer that opens the thing being
/// talked about. Mobile used to collapse all three into one grey note, because
/// the payload columns behind them were never selected.
class ChatEventCard extends StatelessWidget {
  const ChatEventCard({
    super.key,
    required this.message,
    this.viewerId,
    this.isLatestOffer = false,
  });

  final ChatMessage message;

  /// Who's looking. An offer reads differently to the buyer and the seller,
  /// and only the buyer can act on one from here.
  final String? viewerId;

  /// Whether this is the newest card for its offer. Only the last word in a
  /// negotiation carries buttons — an older counter is history.
  final bool isLatestOffer;

  @override
  Widget build(BuildContext context) {
    final listing = message.listingContext;
    if (listing != null) {
      final condition = listing.condition;
      return _EventShell(
        icon: LucideIcons.tag,
        label: 'Tentang Listing',
        stamp: message.eventStamp,
        imageUrl: listing.cardImage,
        title: listing.cardName ?? 'Kartu',
        subtitle: [
          if (condition != null && condition.isNotEmpty)
            CardConditionX.fromRaw(condition).short,
          formatRupiah(listing.priceIdr),
        ].join(' · '),
        footer: listing.packSlug == null ? null : 'Lihat Kartu',
        onTap: listing.packSlug == null
            ? null
            : () => context.push(
                Routes.cardDetail(listing.packSlug!, listing.cardId),
              ),
      );
    }

    final order = message.orderEvent;
    if (order != null) {
      return _EventShell(
        icon: LucideIcons.package,
        label: order.label,
        stamp: message.eventStamp,
        imageUrl: order.cardImage,
        title: order.cardName ?? 'Kartu',
        subtitle: 'x${order.quantity} · ${formatRupiah(order.amountIdr)}',
        footer: 'Lihat Pesanan',
        onTap: () => context.push(Routes.orderDetail(order.matchSlug)),
      );
    }

    final offer = message.offerEvent;
    if (offer != null) {
      return _EventShell(
        icon: LucideIcons.handCoins,
        label: offer.label,
        stamp: message.eventStamp,
        imageUrl: offer.cardImage,
        title: offer.cardName ?? 'Kartu',
        // The listing price is struck through only when the offer sits under
        // it, the same condition as `showStrike` on the web.
        subtitlePrice: (
          price: offer.price,
          strike: offer.showStrike ? offer.listingPrice : null,
          quantity: offer.quantity,
        ),
        note: offer.message,
        // Web gives the seller a link out and the buyer live buttons; the
        // footer decides which, since it needs the offer's current state.
        footerWidget: _OfferFooter(
          event: offer,
          viewerId: viewerId,
          isLatest: isLatestOffer,
        ),
      );
    }

    // A `system` row, or an event whose payload didn't parse.
    return _PlainNote(
      text: message.text.isEmpty ? 'Pembaruan percakapan' : message.text,
    );
  }
}

class _PlainNote extends StatelessWidget {
  const _PlainNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: context.appColors.secondary,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.caption(context.mutedForeground),
          ),
        ),
      ),
    );
  }
}

class _EventShell extends StatelessWidget {
  const _EventShell({
    required this.icon,
    required this.label,
    required this.stamp,
    required this.imageUrl,
    required this.title,
    this.footer,
    this.onTap,
    this.footerWidget,
    this.subtitle,
    this.subtitlePrice,
    this.note,
  });

  final IconData icon;
  final String label;
  final String stamp;
  final String? imageUrl;
  final String title;

  /// The plain one-line detail, for the listing and order cards.
  final String? subtitle;

  /// The offer card's priced line, which needs a struck-through original.
  final ({int price, int? strike, int quantity})? subtitlePrice;

  /// The note the buyer or seller attached to an offer.
  final String? note;

  final String? footer;
  final VoidCallback? onTap;

  /// A footer that does more than link somewhere — the offer card's buttons.
  final Widget? footerWidget;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final noteText = note;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    icon: icon,
                    label: label,
                    stamp: stamp,
                    background: colors.secondary,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Thumb(imageUrl: imageUrl),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySmSemibold(
                                  colors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (subtitlePrice != null)
                                _PriceLine(priced: subtitlePrice!)
                              else if (subtitle != null)
                                Text(
                                  subtitle!,
                                  style: AppTypography.caption(
                                    context.mutedForeground,
                                  ),
                                ),
                              if (noteText != null &&
                                  noteText.trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '"$noteText"',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.caption(
                                    colors.onSurface,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (footerWidget != null)
                    footerWidget!
                  else if (footer != null && onTap != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: colors.secondary,
                        border: Border(
                          top: BorderSide(color: context.borderColor),
                        ),
                      ),
                      child: Text(
                        footer!,
                        textAlign: TextAlign.center,
                        style: AppTypography.captionSemibold(colors.primary),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.label,
    required this.stamp,
    required this.background,
  });

  final IconData icon;
  final String label;
  final String stamp;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: context.appColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.overline(context.mutedForeground),
            ),
          ),
          Text(stamp, style: AppTypography.caption(context.mutedForeground)),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final placeholder = Icon(
      LucideIcons.image,
      size: 18,
      color: context.mutedForeground,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 48,
        height: 48,
        color: context.appColors.secondary,
        child: url == null || url.isEmpty
            ? placeholder
            : Image.network(
                url,
                fit: BoxFit.cover,
                // `object-[center_15%]` on the web — card art reads best from
                // near the top rather than the middle.
                alignment: const Alignment(0, -0.7),
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.priced});

  final ({int price, int? strike, int quantity}) priced;

  @override
  Widget build(BuildContext context) {
    final original = priced.strike;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(
          formatRupiah(priced.price),
          style: AppTypography.bodySmSemibold(context.appColors.onSurface),
        ),
        if (original != null)
          Text(
            formatRupiah(original),
            style: AppTypography.caption(
              context.mutedForeground,
            ).copyWith(decoration: TextDecoration.lineThrough),
          ),
        Text(
          'x${priced.quantity}',
          style: AppTypography.caption(context.mutedForeground),
        ),
      ],
    );
  }
}

/// The offer card's footer — a port of `buildFooter` in `offer-event-card`.
///
/// The seller only gets a way through to their offers list; the buyer gets
/// the live buttons, but only on the newest card for that offer and only
/// while the offer is actually theirs to answer.
class _OfferFooter extends ConsumerStatefulWidget {
  const _OfferFooter({
    required this.event,
    required this.viewerId,
    required this.isLatest,
  });

  final ChatOfferEvent event;
  final String? viewerId;
  final bool isLatest;

  @override
  ConsumerState<_OfferFooter> createState() => _OfferFooterState();
}

class _OfferFooterState extends ConsumerState<_OfferFooter> {
  /// `MAX_COUNTERS_PER_SIDE` in `offer-event-card.tsx`.
  static const _maxCountersPerSide = 5;

  bool _busy = false;

  /// Runs one of the offer RPCs and refreshes what reads them, the same way
  /// the Penawaran list does.
  Future<void> _run(Future<String?> Function() action, String success) async {
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(error ?? success)));
    if (error == null) {
      ref.invalidate(myOffersProvider);
      ref.invalidate(proposalsSummaryProvider);
    }
  }

  Future<void> _accept(ListingOfferModel offer) async {
    await showConfirmDialog(
      context,
      title: 'Terima penawaran ini?',
      description:
          'Kamu akan membeli ${offer.quantity}x kartu seharga '
          '${formatRupiah(offer.currentPrice)} per pcs. Penawaran masuk ke '
          'keranjang dan bisa dibayar bersama pesanan lain. Stok ditahan 24 '
          'jam.',
      confirmLabel: 'Konfirmasi Terima',
      loadingLabel: 'Memproses...',
      destructive: false,
      onConfirm: () => _run(
        () => ref.read(proposalsRepositoryProvider).acceptOffer(offer.slug),
        'Penawaran diterima. Harga spesial aktif 24 jam.',
      ),
    );
  }

  Future<void> _counter(ListingOfferModel offer) async {
    final price = await showCounterPriceDialog(
      context,
      title: 'Tawar balik',
      initialPrice: offer.currentPrice,
    );
    if (price == null || !mounted) return;
    await _run(
      () => ref
          .read(proposalsRepositoryProvider)
          .counterOffer(offerSlug: offer.slug, price: price),
      'Tawaran balik terkirim',
    );
  }

  Future<void> _reject(ListingOfferModel offer) async {
    await showConfirmDialog(
      context,
      title: 'Tolak penawaran ini?',
      description: 'Penjual akan diberi tahu penawaranmu ditolak.',
      confirmLabel: 'Tolak',
      loadingLabel: 'Memproses...',
      onConfirm: () => _run(
        () => ref
            .read(proposalsRepositoryProvider)
            .rejectOffer(offerSlug: offer.slug),
        'Penawaran ditolak',
      ),
    );
  }

  Future<void> _withdraw(ListingOfferModel offer) async {
    await showConfirmDialog(
      context,
      title: 'Tarik penawaran ini?',
      description: 'Penawaran akan dibatalkan dan tidak bisa dilanjutkan.',
      confirmLabel: 'Tarik Penawaran',
      loadingLabel: 'Memproses...',
      onConfirm: () => _run(
        () => ref.read(proposalsRepositoryProvider).withdrawOffer(offer.slug),
        'Penawaran ditarik',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewerId = widget.viewerId;
    if (viewerId == widget.event.sellerId) {
      return _LinkFooter(
        label: 'Lihat & balas penawaran',
        onTap: () => context.push(Routes.sellerProducts),
      );
    }
    if (viewerId != widget.event.buyerId || !widget.isLatest) {
      return const SizedBox.shrink();
    }

    // The live row behind the card, not the frozen snapshot the event holds:
    // a negotiation moves on, and the buttons have to follow the offer's
    // current state rather than what it looked like when this was posted.
    final offer = ref
        .watch(myOffersProvider)
        .valueOrNull
        ?.where((o) => o.slug == widget.event.offerSlug)
        .firstOrNull;
    if (offer == null) return const SizedBox.shrink();

    if (offer.status == OfferStatus.accepted) {
      return _LinkFooter(
        label: 'Selesaikan pembayaran →',
        onTap: () => context.push(Routes.cart),
      );
    }
    if (offer.status != OfferStatus.pending) return const SizedBox.shrink();

    if (offer.lastActor == OfferActor.buyer) {
      return _FooterBar(
        children: [
          Expanded(
            child: Text(
              'Menunggu respon penjual',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _withdraw(offer),
            child: const Text('Tarik'),
          ),
        ],
      );
    }

    // The seller's move is the one waiting on an answer.
    final canCounter = offer.buyerCounterCount < _maxCountersPerSide;
    return _FooterBar(
      children: [
        const Spacer(),
        TextButton(
          onPressed: _busy ? null : () => _reject(offer),
          style: TextButton.styleFrom(foregroundColor: context.appColors.error),
          child: const Text('Tolak'),
        ),
        if (canCounter) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _counter(offer),
            child: const Text('Tawar Balik'),
          ),
        ],
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _busy ? null : () => _accept(offer),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.appSemantic.success,
          ),
          child: const Text('Terima'),
        ),
      ],
    );
  }
}

class _FooterBar extends StatelessWidget {
  const _FooterBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.appColors.secondary,
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Row(children: children),
    );
  }
}

class _LinkFooter extends StatelessWidget {
  const _LinkFooter({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: context.appColors.secondary,
          border: Border(top: BorderSide(color: context.borderColor)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.captionSemibold(context.appColors.primary),
        ),
      ),
    );
  }
}
