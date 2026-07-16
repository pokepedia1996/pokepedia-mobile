import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/card_art.dart';

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
        onTap: () => context.push(Routes.search),
      ),
    );
  }
}

/// Ports `components/home/deckbuilder-promo.tsx`.
class DeckbuilderPromoSection extends StatelessWidget {
  const DeckbuilderPromoSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: _PromoCard(
        eyebrow: 'DECKBUILDER',
        icon: Icons.style_outlined,
        title: 'I wanna be the very best, like no one ever was.',
        description: 'Bangun deckmu sendiri dan jadi juara!',
        ctaLabel: 'Mulai Deckbuilder',
        onTap: () => context.push('${Routes.portfolio}?tab=deck'),
      ),
    );
  }
}

/// Ports `components/home/collection-promo.tsx`.
class CollectionPromoSection extends StatelessWidget {
  const CollectionPromoSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 96,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final angle = (i - 1.5) * 0.12;
                  return Transform.translate(
                    offset: Offset(0, (i - 1.5).abs() * -6),
                    child: Transform.rotate(
                      angle: angle,
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
                        child: SizedBox(
                          width: 56,
                          child: CardArt(borderRadius: AppRadius.sm),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Gotta Catch 'Em All!",
              textAlign: TextAlign.center,
              style: AppTypography.h2(colors.onSurface),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push(Routes.portfolio),
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
          ],
        ),
      ),
    );
  }
}
