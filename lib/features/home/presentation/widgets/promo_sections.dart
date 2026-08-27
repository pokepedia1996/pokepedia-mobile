import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/card_swap.dart';
import '../../../../shared/widgets/marquee.dart';

const _cdn = 'https://cdn2.pokepedia.id';

const _deckFeatures = [
  '$_cdn/features/deck-1.png',
  '$_cdn/features/deck-2.png',
  '$_cdn/features/deck-3.png',
];

const _tournamentSlugs = ['pbl', 'gbl', 'ubl', 'mbl', 'wc'];

List<String> _heroCards(List<int> indices) => [
  for (final i in indices) '$_cdn/hero/sm/$i.webp',
];

final _collectionCards = _heroCards(const [
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  33,
  34,
  35,
  36,
  37,
  38,
  39,
  20,
]);

class _PromoCard extends StatelessWidget {
  const _PromoCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.ctaLabel,
    required this.onTap,
    required this.icon,
  });

  final String eyebrow;
  final String title;
  final String description;
  final String ctaLabel;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(eyebrow, style: AppTypography.overline(colors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: AppTypography.h2(colors.onSurface)),
          const SizedBox(height: 6),
          Text(
            description,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(ctaLabel),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ports `components/home/pencarian-detail-promo.tsx` (simplified to a
/// static promo card — the live filter form/preview fan is out of scope for
/// a dummy-data UI pass).
class SearchPromoSection extends StatelessWidget {
  const SearchPromoSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: _PromoCard(
        eyebrow: 'PENCARIAN LANJUTAN',
        icon: Icons.search,
        title: 'Cari kartu spesifik?',
        description:
            'Filter nama, ilustrator, tipe, rarity, dan lebih banyak lagi.',
        ctaLabel: 'Lihat Semua',
        onTap: () => context.go(Routes.search),
      ),
    );
  }
}

/// Ports `components/home/deckbuilder-promo.tsx` — quote heading over a
/// faint tournament backdrop, tournament badges, and an animated card-swap
/// deck preview (`components/ui/card-swap.tsx`).
class DeckbuilderPromoSection extends StatelessWidget {
  const DeckbuilderPromoSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl2),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: context.borderColor),
            borderRadius: BorderRadius.circular(AppRadius.xl2),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.black, Colors.transparent],
                    stops: [0.4, 1.0],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: Opacity(
                    opacity: 0.12,
                    child: Image.network(
                      '$_cdn/tournament/tournament.webp',
                      fit: BoxFit.cover,
                      color: Colors.grey,
                      colorBlendMode: BlendMode.saturation,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightLine(text: 'I wanna be the very best,'),
                    const SizedBox(height: 4),
                    _HighlightLine(text: 'Like no one ever was.'),
                    const SizedBox(height: 12),
                    Text(
                      'Bangun deckmu sendiri dan jadi juara!',
                      style: AppTypography.bodySm(colors.onSurface),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 44,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (final slug in _tournamentSlugs)
                            Image.network(
                              '$_cdn/tournament/$slug.webp',
                              height: 60,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox.shrink(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Center(
                    //   child: CardSwap(
                    //     imageUrls: _deckFeatures,
                    //     cardWidth: 190,
                    //     cardHeight: 240,
                    //     cardDistance: 26,
                    //     verticalDistance: 30,
                    //   ),
                    // ),
                    // const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            context.go('${Routes.portfolio}?tab=deck'),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Mulai Deckbuilder'),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward, size: 16),
                          ],
                        ),
                      ),
                    ),
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

class _HighlightLine extends StatelessWidget {
  const _HighlightLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(text, style: AppTypography.h2(const Color(0xFF18181B))),
    );
  }
}

/// Ports `components/home/collection-promo.tsx` — the mobile-breakpoint
/// variant (heading, CTA, and a horizontal auto-scrolling marquee of
/// collection card art, since the desktop parallax columns don't apply on
/// a phone form factor).
class CollectionPromoSection extends StatelessWidget {
  const CollectionPromoSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 24),
      child: Column(
        children: [
          Text(
            "Gotta Catch 'Em All!",
            textAlign: TextAlign.center,
            style: AppTypography.h2(colors.onSurface),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go(Routes.portfolio),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Kelola Koleksimu'),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Stack(
            children: [
              SizedBox(
                height: 140,
                child: Marquee(
                  duration: const Duration(seconds: 24),
                  children: [
                    for (final url in _collectionCards)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Image.network(
                            url,
                            height: 140,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 32,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        colors.surface,
                        colors.surface.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 32,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        colors.surface,
                        colors.surface.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
