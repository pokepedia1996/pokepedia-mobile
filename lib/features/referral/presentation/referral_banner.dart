import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../usecase/referral_providers.dart';
import 'referral_style.dart';

/// Akun "Ajak Teman" banner (02 §1). Signed-in only; hidden while the
/// program is paused or before the dashboard answers. Stays cream in dark
/// mode.
class ReferralBanner extends ConsumerWidget {
  const ReferralBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref
        .watch(referralDashboardProvider(ReferralFilter.all))
        .valueOrNull;
    if (dashboard == null || !dashboard.enabled) return const SizedBox.shrink();
    final prize = formatRupiah(dashboard.maxPrize);

    const heading = TextStyle(
      fontFamily: 'CalSans',
      fontSize: 16,
      color: ReferralColors.ink,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Material(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFEDE6D6)),
        ),
        color: ReferralColors.cream,
        child: Semantics(
          button: true,
          label: 'Ajak Teman: dapatkan hingga $prize untuk tiap teman',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => context.push(Routes.referral),
            child: Ink(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(
                    '$referralImageDir/pattern-energi-tile-krem.webp',
                  ),
                  repeat: ImageRepeat.repeat,
                  scale: 2,
                ),
              ),
              // A floor, not a fixed height: larger text grows the banner
              // instead of clipping it.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 116),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      right: 14,
                      top: -4,
                      child: Image.asset(
                        '$referralImageDir/hero-coretan.webp',
                        width: 148,
                        height: 138,
                        fit: BoxFit.contain,
                        cacheWidth:
                            (148 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Dapatkan hingga', style: heading),
                          const SizedBox(height: 2),
                          CustomPaint(
                            foregroundPainter: _Underline(),
                            child: Text(
                              prize,
                              style: const TextStyle(
                                fontFamily: 'CalSans',
                                fontSize: 29,
                                color: ReferralColors.red,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              const Text('untuk tiap teman', style: heading),
                              const SizedBox(width: 6),
                              Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: ReferralColors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  LucideIcons.arrowRight,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// shortcut: static two-stroke underline instead of the animated
/// `banner_underline` scribble (needs onboarding_scribble.json); swap in
/// ScribbleDrawing when onboarding lands.
class _Underline extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ReferralColors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final y = size.height - 1;
    canvas.drawPath(
      Path()
        ..moveTo(0, y)
        ..quadraticBezierTo(size.width * 0.5, y - 4, size.width, y - 1),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.1, y + 4)
        ..quadraticBezierTo(size.width * 0.55, y + 1, size.width * 0.9, y + 3),
      paint..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(_Underline oldDelegate) => false;
}
