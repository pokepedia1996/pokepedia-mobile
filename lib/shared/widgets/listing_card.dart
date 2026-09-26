import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router/routes.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/card_ownership_controller.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../features/portfolio/usecase/portfolio_notifier.dart';
import '../models/listing_model.dart';
import 'card_art.dart';
import 'card_language_badge.dart';
import 'condition_badge.dart';
import 'reputation_star.dart';
import 'seller_avatar.dart';
import 'wishlist_heart.dart';

/// Ports `features/market/ui/storefront-listing-card.tsx` — a marketplace
/// listing tile with a wishlist badge, condition, language/variant, price,
/// relative time, and seller footer. Every call site here passes a `buyable
/// = false` context (transactions are covered later), so the quantity
/// selector / "Tambah ke Keranjang" button web shows for buyable listings
/// is intentionally omitted, mirroring how the web marketplace grid itself
/// renders this component with `buyable={false}`.
/// The grid geometry [ListingCard] needs, computed from the cell width
/// rather than set as an aspect ratio.
///
/// A card is artwork (a fixed 245:342) plus rows of text whose height does
/// not scale with the screen. One `childAspectRatio` therefore can't be
/// right on more than one device: tight on a 390pt phone, it overflows on a
/// 360pt one, and loose enough to be safe there it leaves a gap on tablets.
///
/// The constants come from measuring the card, in
/// `test/listing_card_height_test.dart`, which fails if the layout grows
/// past them.
SliverGridDelegate listingGridDelegate(
  BuildContext context, {
  required bool showSeller,
  int columns = 2,
  double spacing = 12,
  double horizontalPadding = 16,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final cell =
      (width - horizontalPadding * 2 - spacing * (columns - 1)) / columns;

  // The artwork sits inside the card's 8pt padding on each side.
  final art = (cell - 16) * 342 / 245;

  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: spacing,
    crossAxisSpacing: spacing,
    mainAxisExtent:
        art + (showSeller ? listingCardChrome : listingCardChromeNoSeller),
  );
}

/// Everything in the card that isn't artwork: the three text rows, the
/// card's padding, and the seller strip.
///
/// Measured, not guessed — `listing_card_height_test` measures where the
/// card's content actually ends and fails the build when this drifts under
/// it. It went 149 -> 165 when the verified badge and reputation star moved
/// out of the seller row and became their own lines in the column, then
/// 165 -> 142 when the side badge, the available count and the offers pill
/// all stopped needing rows of their own.
///
/// **A grid cell is one height for every tile in it**, so this fits the
/// tallest — which means anything only *some* listings carry is a row every
/// listing pays for, and the ones without it wear the difference as white
/// space. That is why the offers pill sits on the artwork now: as its own
/// row it cost every cell in the grid ~29pt to serve a minority of them.
/// Measured need is 137.3, and it is the same whether or not the listing
/// accepts offers or names a city.
const listingCardChrome = 142.0;

/// The same without the seller strip (`showSeller: false`).
///
/// 101 against a measured 96.3 — the price row plus the gap that trails it,
/// which a first measurement read as 92.3 by stopping at the last glyph
/// instead of the last box. The margin is deliberate: an earlier value sat
/// 0.8pt above its measurement and overflowed by three points on some runs
/// only, which is worse than failing on all of them.
const listingCardChromeNoSeller = 101.0;

class ListingCard extends ConsumerStatefulWidget {
  const ListingCard({
    super.key,
    required this.listing,
    this.onTap,
    this.showSeller = true,
  });

  final ListingModel listing;

  /// Overrides the tap destination. When omitted, mirrors web's
  /// `linkHref` fallback: a WTB (bid) listing opens the regular card page,
  /// a WTS (ask) listing opens the seller-scoped "product" page — since
  /// only that seller's copy, condition, and price are relevant there.
  final VoidCallback? onTap;
  final bool showSeller;

  @override
  ConsumerState<ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends ConsumerState<ListingCard> {
  bool _wishlistToggling = false;

  Future<void> _toggleWishlist(bool wishlisted) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      context.push(Routes.login);
      return;
    }
    setState(() => _wishlistToggling = true);
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .setWishlisted(widget.listing.card.id, !wishlisted);
    if (!mounted) return;
    setState(() => _wishlistToggling = false);

    // Without this the heart just snaps back on the next rebuild, which
    // reads as the tap not registering rather than the write failing.
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error), persist: false));
    }
  }

  void _handleTap(BuildContext context) {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    final listing = widget.listing;
    if (listing.side == ListingSide.bid) {
      // A wanted-ad has its own page now. Without a slug there's nothing to
      // look it up by, so the catalog card page stays the fallback — that's
      // where web's `linkHref` sends every bid.
      if (listing.slug.isEmpty) {
        context.push(Routes.cardDetail(listing.card.packSlug, listing.card.id));
      } else {
        context.push(Routes.bidListing(listing.slug));
      }
    } else if (listing.storeSlug.isEmpty) {
      context.push(Routes.cardDetail(listing.card.packSlug, listing.card.id));
    } else {
      context.push(Routes.storeCardDetail(listing.storeSlug, listing.card.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final colors = context.appColors;
    final semantic = context.appSemantic;
    final isBid = listing.side == ListingSide.bid;
    final wishlisted = ref.watch(isWishlistedProvider(listing.card.id));

    return InkWell(
      onTap: () => _handleTap(context),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            // Loose, so the artwork yields rather than the card overflowing.
            //
            // [listingCardChrome] is a measurement, and a measurement taken
            // in a test harness cannot be exact on a device: the harness
            // draws a fallback font, the device draws Urbanist, and the
            // reader's own text-size setting scales all of it afterwards.
            // Every version of this constant has eventually been a point or
            // two short of some real tile, and each bump bought that back by
            // padding every cell in the grid with white space.
            //
            // So the text block takes what it needs and the artwork absorbs
            // the remainder. Losing a pixel off a card image nobody is
            // measuring is invisible; a yellow overflow bar is not.
            Flexible(
              child: Stack(
                children: [
                  CardArt(imageUrl: listing.card.imageUrl),
                  Positioned(
                    right: 6,
                    top: 6,
                    // How many, then what grade — the count qualifies the
                    // grade beside it ("two, both Near Mint"), so it leads.
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (listing.quantity > 1) ...[
                          _QuantityChip(quantity: listing.quantity),
                          const SizedBox(width: 4),
                        ],
                        ConditionBadge(condition: listing.condition),
                      ],
                    ),
                  ),
                  if (listing.isFeatured)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          border: Border.all(
                            color: colors.primary.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          'Unggulan',
                          style: AppTypography.badge(colors.primary),
                        ),
                      ),
                    ),
                  Positioned(
                    // Flush with the artwork's corner, which is where web's
                    // `left-2 top-2` puts it: that offset is measured from the
                    // card, whose 8px padding is exactly where the image
                    // starts. Dropping to the image's own corner instead of
                    // insetting again is what closes the gap.
                    left: 0,
                    top: listing.isFeatured ? 36 : 0,
                    child: _WishlistBadge(
                      wishlisted: wishlisted,
                      loading: _wishlistToggling,
                      onTap: _wishlistToggling
                          ? null
                          : () => _toggleWishlist(wishlisted),
                    ),
                  ),
                  // On the artwork, not under it, for the same reason
                  // "Unggulan" above is: a grid cell is one height for every
                  // tile in it, so a row that only *some* listings carry is a
                  // row every listing pays for. As its own line this cost the
                  // grid ~29pt per cell, and the tiles without it wore that as
                  // white space under the seller. Here it costs nothing.
                  if (listing.acceptsOffers)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          // Opaque, unlike the in-flow pill it replaces: it now
                          // sits on artwork rather than on the card's surface,
                          // and a 6%-alpha fill over a holographic Pokémon card
                          // is not a background, it's a smudge.
                          color: Theme.of(context).cardColor,
                          border: Border.all(color: context.borderColor),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          'dengan penawaran',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.badge(context.mutedForeground),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Row 1 — the card's name, on a line of its own.
            Text(
              listing.card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
            const SizedBox(height: 4),

            // Row 2 — where the print is from, and which side of the book
            // it is on. The side badge is the one thing on this line that
            // must never clip, so it takes its own width and the provenance
            // beside it gives way instead.
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      CardLanguageBadge(language: listing.card.language),
                      const SizedBox(width: 4),
                      // _setSymbol(context, listing),
                      Flexible(
                        child: Text(
                          listing.card.expansionCode.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          listing.card.collectorNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isBid ? semantic.bid : semantic.ask,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  // "WTB"/"WTS", not "BID (WTB)". On a tile the reader is
                  // scanning, not trading: the side is a label to recognise
                  // at a glance, and the parenthetical was the half of it
                  // that everyone actually reads.
                  child: Text(
                    isBid ? 'WTB' : 'WTS',
                    maxLines: 1,
                    style: AppTypography.badge(Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Row 3 — the price, with how much is on offer against it.
            //
            // The price is never clipped or ellipsised: a price the reader
            // has to guess the end of is worse than no price. Where the row
            // genuinely runs out of room it scales down instead, the way
            // [CardPriceNote] does — every digit still there, just smaller.
            // That matters most at the narrow end, where this size (a step up
            // from the rest of the tile, because the price is what the tile
            // is for) is widest.
            Row(
              children: [
                Flexible(
                  flex: 3,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatRupiah(listing.price),
                      maxLines: 1,
                      style: AppTypography.price(
                        colors.onSurface,
                      ).copyWith(fontSize: 19),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  flex: 2,
                  child: Text(
                    '${listing.available} ${isBid ? "Dicari" : "Tersedia"}',
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            if (widget.showSeller && listing.storeSlug.isNotEmpty) ...[
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.borderColor)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Who is selling comes first, then what is known
                      // about them: the tick, then the reputation star.
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              listing.storeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.captionSemibold(
                                colors.onSurface,
                              ),
                            ),
                          ),
                          if (listing.isVerified) ...[
                            const SizedBox(width: 3),
                            Icon(
                              LucideIcons.badgeCheck,
                              size: 13,
                              color: colors.primary,
                            ),
                          ],
                          const SizedBox(width: 4),
                          ReputationStar(score: listing.sellerFeedbackScore),
                        ],
                      ),
                      // The city sits under the name rather than standing in
                      // for it, so it reads as the detail it is. The pin is
                      // what makes it read as a place at a glance rather than
                      // as a second line of the shop's name.
                      if (listing.cityName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.mapPin,
                              size: 11,
                              color: context.mutedForeground,
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                listing.cityName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The expansion's set symbol, when it has one. The code beside it names
  /// the expansion either way, so a missing symbol draws nothing rather than
  /// repeating that code.
  Widget _setSymbol(BuildContext context, ListingModel listing) {
    final url = listing.expansionSetSymbolUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: SvgPicture.network(
        url,
        height: 14,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }
}

class _WishlistBadge extends StatelessWidget {
  const _WishlistBadge({
    required this.wishlisted,
    required this.loading,
    required this.onTap,
  });

  final bool wishlisted;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: wishlisted
              ? Colors.red
              : Theme.of(context).cardColor.withValues(alpha: 0.9),
          border: wishlisted ? null : Border.all(color: context.borderColor),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: loading
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: wishlisted ? Colors.white : context.mutedForeground,
                ),
              )
            : WishlistHeart(
                active: wishlisted,
                size: 16,
                color: wishlisted ? Colors.white : context.mutedForeground,
              ),
      ),
    );
  }
}

/// The `x2` chip over the artwork: how many copies this listing covers.
///
/// Monochrome for the same reason [ConditionBadge] is — it sits on card art
/// of every colour, and black on white is the one pairing that reads over all
/// of it. Only drawn past one: "x1" is the default every listing would carry,
/// and a badge every tile wears tells the reader nothing.
class _QuantityChip extends StatelessWidget {
  const _QuantityChip({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text('\u00d7$quantity', style: AppTypography.badge(Colors.black)),
    );
  }
}
