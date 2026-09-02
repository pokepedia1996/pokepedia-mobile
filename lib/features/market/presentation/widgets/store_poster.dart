import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/listing_model.dart';
import '../../../../shared/models/store_model.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../../../shared/widgets/seller_avatar.dart';

/// Below this, the sold count is omitted from the poster entirely.
const _minSoldToShow = 5;

/// Which side of the seller's book the poster is advertising.
enum PosterSide {
  /// What the store is selling.
  wts('WTS', 'Dijual'),

  /// What the store is buying.
  wtb('WTB', 'Dicari');

  const PosterSide(this.badge, this.label);

  final String badge;
  final String label;

  ListingSide get listingSide =>
      this == PosterSide.wts ? ListingSide.ask : ListingSide.bid;
}

/// The shareable store poster: a store header, a grid of cards with their
/// condition and price, and the site footer.
///
/// Rendered off-screen and captured to PNG, so it is deliberately built at a
/// fixed size rather than to the phone's width — a poster that reflows with
/// the device would produce a different image per handset.
/// Ten posters is the ceiling — past that a "poster" is a catalogue nobody
/// scrolls, and the share sheet starts choking on attachments.
const maxPosterPages = 10;

/// Splits a store's listings into poster-sized pages, capped at
/// [maxPosterPages].
///
/// The first page is one card short of the rest: its last slot goes to the
/// "+N lainnya" tile, because that page is the one posted on its own and has
/// to say how much more the store is holding. Paginating it as a full page
/// would leave the card that tile displaces on no poster at all.
List<List<ListingModel>> paginateForPoster(List<ListingModel> listings) {
  if (listings.isEmpty) return const [];
  if (listings.length <= StorePoster.capacity) return [listings];

  final first = StorePoster.capacity - 1;
  final pages = [listings.take(first).toList()];
  for (
    var i = first;
    i < listings.length && pages.length < maxPosterPages;
    i += StorePoster.capacity
  ) {
    pages.add(listings.skip(i).take(StorePoster.capacity).toList());
  }
  return pages;
}

/// The `totalCount` a given page reports, which is what decides whether it
/// draws a "+N lainnya" tile.
///
/// Page one carries the whole store's remainder: it is what the sheet
/// selects by default and what gets posted alone, so it is the page that has
/// to point at the rest. The pages after it are read as part of a set and
/// count only themselves — repeating the remainder there would tell a reader
/// who has all the images that they are still missing most of them. Only the
/// final page adds anything back, and only what the [maxPosterPages] cap
/// left behind.
int posterPageTotal(List<List<ListingModel>> pages, int index, int total) {
  if (index == 0) return total;

  final shownThrough = pages
      .take(index + 1)
      .fold<int>(0, (sum, page) => sum + page.length);
  final leftover = index == pages.length - 1 ? total - shownThrough : 0;
  return pages[index].length + leftover;
}

class StorePoster extends StatelessWidget {
  const StorePoster({
    super.key,
    required this.store,
    required this.listings,
    required this.side,
    this.totalCount,
    this.positivePct,
    this.feedbackScore = 0,
  });

  final StoreModel store;

  /// The tiles to draw. Capped by the caller; [totalCount] carries the real
  /// figure so the last tile can say how many didn't fit.
  final List<ListingModel> listings;

  final PosterSide side;
  final int? totalCount;

  /// Reputation isn't on [StoreModel] — the listing page resolves it
  /// separately — so it's passed in rather than re-fetched here.
  final double? positivePct;
  final int feedbackScore;

  /// A 4:5 canvas — the aspect most social feeds show without cropping.
  static const width = 1080.0;
  static const height = 1350.0;

  static const _columns = 4;
  static const _rows = 3;

  /// How many tiles fit before the "+N lainnya" tile takes the last slot.
  static int get capacity => _columns * _rows;

  @override
  Widget build(BuildContext context) {
    final total = totalCount ?? listings.length;
    // Reserve the last slot for the "+N" tile unless everything fits, then
    // count the overflow against what is actually *drawn* — counting it
    // against the list passed in under-reports by the tile the "+N" itself
    // displaced.
    final fits = total <= capacity && listings.length <= capacity;
    final tiles = fits ? listings : listings.take(capacity - 1).toList();
    final overflow = total - tiles.length;

    return Container(
      width: width,
      height: height,
      // Fixed light ground rather than the app theme: this is an image that
      // will be seen outside the app, where the reader's dark mode has no
      // say over how it renders.
      color: const Color(0xFFF7F8FA),
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            store: store,
            side: side,
            positivePct: positivePct,
            feedbackScore: feedbackScore,
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: _columns,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              childAspectRatio: 245 / 342,
              children: [
                for (final listing in tiles) _PosterTile(listing: listing),
                if (overflow > 0) _MoreTile(count: overflow),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Belanja aman tanpa potongan di pokepedia.id',
                  style: AppTypography.h3(const Color(0xFF5A6270)),
                ),
              ),
              const SizedBox(width: 16),
              // The wordmark in the bottom corner, so a screenshot that
              // loses the caption still carries the source.
              Image.asset(
                'assets/images/horizontal-logo-light.webp',
                height: 44,
                filterQuality: FilterQuality.high,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.store,
    required this.side,
    required this.positivePct,
    required this.feedbackScore,
  });

  final StoreModel store;
  final PosterSide side;
  final double? positivePct;
  final int feedbackScore;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF15171D);
    const muted = Color(0xFF5A6270);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SellerAvatar(imageUrl: store.logoUrl, name: store.storeName, size: 72),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store.storeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.h1(ink).copyWith(fontSize: 40),
              ),
              const SizedBox(height: 4),
              if (store.cityName.isNotEmpty)
                Row(
                  children: [
                    const Icon(LucideIcons.mapPin, size: 20, color: muted),
                    const SizedBox(width: 4),
                    Text(
                      store.cityName,
                      style: AppTypography.bodySm(muted).copyWith(fontSize: 20),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              // Wrap, not Row: score, positive-percentage and sold-count are
              // all variable width, and a poster is a fixed canvas — an
              // overflow here would be baked into the shared image.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (feedbackScore > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.star,
                          size: 20,
                          color: Color(0xFFE0A83A),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$feedbackScore',
                          style: AppTypography.bodySmSemibold(
                            ink,
                          ).copyWith(fontSize: 20),
                        ),
                      ],
                    ),
                  if (positivePct != null)
                    Text(
                      '${positivePct!.round()}% positif',
                      style: AppTypography.bodySm(muted).copyWith(fontSize: 20),
                    ),
                  // Under five sales is not a number worth advertising —
                  // it reads as "nobody buys here" rather than as traction.
                  if (store.itemsSoldCount >= _minSoldToShow)
                    Text(
                      '${store.itemsSoldCount} terjual',
                      style: AppTypography.bodySm(muted).copyWith(fontSize: 20),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ConstrainedBox(
          // A long handle would otherwise push the whole header wider than
          // the canvas.
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: side == PosterSide.wts
                      ? const Color(0xFF0B6F5C)
                      : const Color(0xFF2F56E0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  side.badge,
                  style: AppTypography.h3(Colors.white).copyWith(fontSize: 26),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'pokepedia.id/market/${store.handle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(muted).copyWith(fontSize: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({required this.listing});

  final ListingModel listing;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardArt(imageUrl: listing.card.imageUrl, borderRadius: AppRadius.md),

          // Condition, abbreviated — "NM" reads at poster scale where "Near
          // Mint" would wrap or shrink.
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                listing.condition.short,
                style: AppTypography.badge(Colors.white).copyWith(fontSize: 16),
              ),
            ),
          ),

          // Price sits *on* the art rather than under it, which buys the
          // grid a full row of height. The scrim is what keeps it legible
          // over a light card — a plain label on artwork is a coin flip.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xE6000000)],
                ),
              ),
              child: Text(
                formatRupiah(listing.price),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmSemibold(
                  Colors.white,
                ).copyWith(fontSize: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The last tile when the store has more than fits — "+100 lainnya".
class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8EBF0),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '+$count',
            style: AppTypography.h1(
              const Color(0xFF15171D),
            ).copyWith(fontSize: 44),
          ),
          Text(
            'lainnya',
            style: AppTypography.bodySm(
              const Color(0xFF5A6270),
            ).copyWith(fontSize: 22),
          ),
        ],
      ),
    );
  }
}
