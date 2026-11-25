import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_palette.dart';
import '../../../../shared/widgets/app_network_image.dart';
import '../../../ads/repository/ads_repository.dart';
import '../../../ads/usecase/ad_link.dart';
import '../../../ads/usecase/ads_notifier.dart';

/// One of Beranda's banners: a booking from the `ads` table.
class HomeBanner {
  const HomeBanner({
    required this.imageUrl,
    required this.label,
    required this.open,
  });

  /// Its creative, its advertiser as the label, and its `href` (see
  /// [AdLinkTarget.parse]).
  factory HomeBanner.fromAd(AdModel ad) => HomeBanner(
    imageUrl: ad.imageUrl,
    label: ad.companyName,
    open: (context) => openAdLink(context, ad.href),
  );

  final String imageUrl;

  /// What the artwork says, for screen readers.
  final String label;
  final void Function(BuildContext context) open;
}

/// The swipeable banner row under the portfolio: one banner at a time with
/// the next one peeking in, and dots marking which is in view.
///
/// Its banners are what the `ads` table has booked for `home` today, in
/// `slot_position` order. Nothing booked, or the bookings not read, and the
/// row is not there at all — its gap below included.
class HomeBannerCarousel extends ConsumerStatefulWidget {
  const HomeBannerCarousel({super.key, this.banners});

  /// In place of the bookings.
  final List<HomeBanner>? banners;

  /// The space between the row and the section under it.
  static const bottomGap = 14.0;

  @override
  ConsumerState<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends ConsumerState<HomeBannerCarousel> {
  /// The design's 340×150 banner on a 430-wide screen: the same share of the
  /// width on any phone, so the next banner always shows its edge.
  static const _widthShare = 340 / 430;
  static const _aspect = 340 / 150;

  /// Space between the screen's edge and the banner in view, which is also
  /// the gap between two banners.
  static const _gutter = 16.0;

  PageController? _controller;
  double _viewport = 0;
  int _page = 0;

  List<HomeBanner> get _banners =>
      widget.banners ??
      [
        for (final ad
            in ref.watch(adsProvider(AdPlacement.home)).valueOrNull ??
                const <AdModel>[])
          HomeBanner.fromAd(ad),
      ];

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  PageController _controllerFor(double viewport, double pageWidth) {
    if (_controller == null || viewport != _viewport) {
      final previous = _controller;
      _viewport = viewport;
      _controller = PageController(
        viewportFraction: pageWidth / viewport,
        initialPage: _page,
      );
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    }
    return _controller!;
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final banners = _banners;
    if (banners.isEmpty) return const SizedBox.shrink();
    // A refresh can bring back fewer bookings than the page in view.
    if (_page >= banners.length) _page = 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final bannerWidth = viewport * _widthShare;
        final controller = _controllerFor(viewport, bannerWidth + _gutter);

        return Padding(
          padding: const EdgeInsets.only(bottom: HomeBannerCarousel.bottomGap),
          child: Column(
            children: [
              SizedBox(
                height: bannerWidth / _aspect,
                child: PageView.builder(
                  controller: controller,
                  padEnds: false,
                  itemCount: banners.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(left: _gutter),
                    child: _BannerTile(banner: banners[i]),
                  ),
                ),
              ),
              if (banners.length > 1) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < banners.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: i == _page ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _page ? palette.brand : palette.border,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BannerTile extends StatelessWidget {
  const _BannerTile({required this.banner});

  final HomeBanner banner;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: banner.label,
      child: GestureDetector(
        onTap: () => banner.open(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(
            color: DesignPalette.of(context).chip,
            child: cachedNetworkImage(
              banner.imageUrl,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
