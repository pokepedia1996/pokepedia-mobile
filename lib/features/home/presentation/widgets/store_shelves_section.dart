import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../core/utils/image_url.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/listing_model.dart';
import '../../../../shared/models/store_model.dart';
import '../../../../shared/widgets/app_network_image.dart';
import '../../repository/home_repository.dart';
import '../../repository/models/store_shelf.dart';
import '../../usecase/store_shelves_notifier.dart';
import 'home_section_header.dart';

/// "Listing baru dari toko": the stores that listed most recently, each with
/// its newest listings on a shelf. More stores load as the page nears its
/// end — see `HomePage`, which watches the scroll.
class StoreShelvesSection extends ConsumerWidget {
  const StoreShelvesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = DesignPalette.of(context);
    final async = ref.watch(storeShelvesProvider);
    final state = async.valueOrNull;

    // Nothing to show at all — the first page failed or came back empty —
    // and the section steps aside rather than leave a heading over nothing.
    if (state == null && !async.isLoading) return const SizedBox.shrink();
    if (state != null && state.shelves.isEmpty && !state.hasMore) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeSectionHeader(title: 'Listing baru dari toko'),
          const SizedBox(height: 4),
          for (final shelf in state?.shelves ?? const <StoreShelf>[])
            StoreShelfTile(shelf: shelf),
          if (state == null || state.loadingMore)
            const _Loading()
          else if (state.moreFailed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: TextButton(
                  onPressed: () =>
                      ref.read(storeShelvesProvider.notifier).retry(),
                  child: Text(
                    'Gagal memuat toko lainnya. Coba lagi',
                    style: GoogleFonts.urbanist(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.brand,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.muted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Memuat toko lainnya...',
            style: GoogleFonts.urbanist(fontSize: 13, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

/// One store: who it is, then its newest listings.
@visibleForTesting
class StoreShelfTile extends StatelessWidget {
  const StoreShelfTile({super.key, required this.shelf});

  final StoreShelf shelf;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final store = shelf.store;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: store.handle.isEmpty
                ? null
                : () => context.push(Routes.storeDetail(store.handle)),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                _StoreAvatar(store: store),
                const SizedBox(width: 10),
                Expanded(child: _StoreInfo(store: store)),
                Icon(LucideIcons.chevronRight, size: 18, color: palette.muted),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            // No bottom padding: the price pills' 10px lift over the art
            // leaves that room below them already.
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
            decoration: BoxDecoration(
              color: palette.chip,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < storeShelfListingCount; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    // A store with fewer listings than slots keeps the tiles
                    // their usual size, with the room left empty.
                    child: i < shelf.listings.length
                        ? _ListingTile(listing: shelf.listings[i])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreInfo extends StatelessWidget {
  const _StoreInfo({required this.store});

  final StoreModel store;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final ratings = store.feedbackScore;
    final meta = [
      if (store.positivePct case final pct?) '${pct.round()}% positif',
      if (store.cityName.isNotEmpty) store.cityName,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                store.storeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.urbanist(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ),
            if (ratings != null && ratings > 0) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.star_rounded,
                size: 16,
                color: Color(0xFFF59E0B),
              ),
              const SizedBox(width: 2),
              Text(
                '$ratings',
                style: GoogleFonts.urbanist(fontSize: 12, color: palette.muted),
              ),
            ],
          ],
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.urbanist(fontSize: 12, color: palette.muted),
          ),
        ],
      ],
    );
  }
}

/// The store's logo, else its owner's avatar, else its initials.
class _StoreAvatar extends StatelessWidget {
  const _StoreAvatar({required this.store});

  final StoreModel store;

  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final image = store.logoUrl ?? store.avatarUrl;
    final initials = Text(
      initialsOf(store.storeName),
      style: GoogleFonts.urbanist(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: palette.ink,
      ),
    );
    return Container(
      width: 40,
      height: 40,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.chip,
        shape: BoxShape.circle,
        border: Border.all(color: palette.border),
      ),
      child: image == null || image.isEmpty
          ? initials
          : cachedNetworkImage(
              image,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => initials,
            ),
    );
  }
}

/// A listing on a shelf: its card (or photo), with the price pinned over the
/// bottom edge.
class _ListingTile extends StatelessWidget {
  const _ListingTile({required this.listing});

  final ListingModel listing;

  void _open(BuildContext context) {
    // The same destinations as the market's own tile (`ListingCard`).
    if (listing.isCustom) {
      if (listing.storeSlug.isEmpty || listing.slug.isEmpty) return;
      context.push(Routes.customListing(listing.storeSlug, listing.slug));
    } else if (listing.storeSlug.isEmpty) {
      context.push(Routes.cardDetail(listing.card.packSlug, listing.card.id));
    } else {
      context.push(Routes.storeCardDetail(listing.storeSlug, listing.card.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final image = listing.tileImageUrl;

    return GestureDetector(
      onTap: () => _open(context),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 245 / 342,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x301C1413),
                    offset: Offset(0, 3),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: image == null
                  ? null
                  : cachedNetworkImage(
                      image,
                      size: ImageSize.half,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
          ),
          // Pulled up over the art's bottom edge, as the design overlaps them.
          Transform.translate(
            offset: const Offset(0, -10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x201C1413),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatRupiah(listing.price),
                  maxLines: 1,
                  style: GoogleFonts.urbanist(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
