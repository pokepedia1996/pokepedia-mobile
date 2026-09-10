import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/marquee.dart';

const _cdn = 'https://cdn2.pokepedia.id';
String _cardUrl(int i) => '$_cdn/hero/sm/$i.webp';

List<String> _range(int start, int end) => [
  for (var i = start; i <= end; i++) _cardUrl(i),
];

final _rowA = _range(42, 53);
final _rowB = _range(0, 11);
final _rowC = _range(21, 32);

/// Ports `components/home/hero-card-wall.tsx` + `hero-wall-marquees.tsx` —
/// a diagonal wall of auto-scrolling card art behind the hero copy, with a
/// staggered fade/slide-in entrance for the logo, heading and CTA.
class HeroSection extends StatefulWidget {
  const HeroSection({super.key});

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _fade(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  Animation<Offset> _slide(double start, double end) =>
      Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ClipRect(
      child: SizedBox(
        height: 420,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.surface),

            // Diagonal auto-scrolling card wall.
            Positioned.fill(
              child: Transform.rotate(
                angle: -0.21,
                child: Transform.scale(
                  scale: 1.6,
                  child: Opacity(
                    opacity: 0.5,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _wallRow(_rowA, const Duration(seconds: 34)),
                        const SizedBox(height: 12),
                        _wallRow(
                          _rowB,
                          const Duration(seconds: 27),
                          reverse: true,
                        ),
                        const SizedBox(height: 12),
                        _wallRow(_rowC, const Duration(seconds: 31)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Legibility gradients.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.surface,
                      colors.surface.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.35],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      colors.surface,
                      colors.surface.withValues(alpha: 0.15),
                    ],
                    stops: const [0.0, 0.85],
                  ),
                ),
              ),
            ),

            // Copy.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _fade(0.0, 0.5),
                    child: SlideTransition(
                      position: _slide(0.0, 0.5),
                      child: Text(
                        'pokepedia.id',
                        style: AppTypography.h3(colors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeTransition(
                    opacity: _fade(0.15, 0.65),
                    child: SlideTransition(
                      position: _slide(0.15, 0.65),
                      child: Text(
                        'Pusatnya jual beli kartu Pokemon di Indonesia.',
                        style: AppTypography.h1(colors.onSurface),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeTransition(
                    opacity: _fade(0.4, 0.9),
                    child: SlideTransition(
                      position: _slide(0.4, 0.9),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => context.go(Routes.market),
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.full,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Jelajahi Market'),
                              SizedBox(width: 6),
                              Icon(LucideIcons.arrowRight, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wallRow(
    List<String> urls,
    Duration duration, {
    bool reverse = false,
  }) {
    return SizedBox(
      height: 100,
      child: Marquee(
        duration: duration,
        reverse: reverse,
        children: [
          for (final url in urls)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.network(
                url,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
