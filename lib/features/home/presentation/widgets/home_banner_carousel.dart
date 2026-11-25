import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/design_palette.dart';

/// One of Beranda's banners: its artwork and where a tap goes.
class HomeBanner {
  const HomeBanner({
    required this.asset,
    required this.label,
    required this.open,
  });

  final String asset;

  /// What the artwork says, for screen readers.
  final String label;
  final void Function(BuildContext context) open;
}

/// The banners, in the design's order. The design's "Tersedia di App Store"
/// and "Tersedia di Google Play" banners are left out: they ask a reader to
/// install the app they are already in.
final homeBanners = <HomeBanner>[
  HomeBanner(
    asset: 'assets/images/home/banner-jual.png',
    label: 'Jual kartu, 0% potongan',
    // Jual is a tab of its own.
    open: (context) => context.go(Routes.seller),
  ),
  HomeBanner(
    asset: 'assets/images/home/banner-scan.png',
    label: 'Scan kartu tanpa batas',
    open: (context) => context.push(Routes.scan),
  ),
  HomeBanner(
    asset: 'assets/images/home/banner-deckbuilder.png',
    label: 'Rakit deck pakai Deckbuilder',
    open: (context) => context.push(Routes.decks),
  ),
];

/// The swipeable banner row under the portfolio: one banner at a time with
/// the next one peeking in, and dots marking which is in view.
class HomeBannerCarousel extends StatefulWidget {
  const HomeBannerCarousel({super.key, this.banners});

  /// Defaults to [homeBanners].
  final List<HomeBanner>? banners;

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
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

  List<HomeBanner> get _banners => widget.banners ?? homeBanners;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final bannerWidth = viewport * _widthShare;
        final controller = _controllerFor(viewport, bannerWidth + _gutter);

        return Column(
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
          child: Image.asset(
            banner.asset,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}
