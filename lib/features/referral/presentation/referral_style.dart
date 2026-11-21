import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/utils/formatters.dart';
import '../repository/models/referral_models.dart';

/// Ajak Teman palette from design 03/04. Fixed colours: the red header, the
/// cream pack screen and the banner stay the same in dark mode.
class ReferralColors {
  ReferralColors._();

  static const red = Color(0xFFAC403A);
  static const maroon = Color(0xFF5E1F1B);
  static const ink = Color(0xFF1C1413);
  static const muted = Color(0xFF6B6564);
  static const cream = Color(0xFFF5EFE1);
  static const codeBg = Color(0xFFFFF6E6);
  static const codeLine = Color(0xFFF1D9B5);
  static const rowTint = Color(0xFFFDF6EA);
  static const pillGold = Color(0xFFF4B63F);
  static const pillGoldText = Color(0xFF5A3A00);
  static const oddsTrack = Color(0xFFF4F1E8);
  static const sheetBg = Color(0xFFFFFBF4);
  static const green = Color(0xFF2E8B57);
  static const border = Color(0xFFEDE6D6);
}

/// Per-tier colours (03 tier table).
class TierStyle {
  const TierStyle({
    required this.cardBg,
    required this.cardEdge,
    required this.ink,
    required this.pillBg,
    required this.pillText,
    required this.bar,
    required this.icon,
    required this.glow,
  });

  final Color cardBg, cardEdge, ink, pillBg, pillText, bar, glow;
  final IconData icon;

  static TierStyle of(ReferralTierKey key) => switch (key) {
    ReferralTierKey.biasa => const TierStyle(
      cardBg: Color(0xFFF4E7D8),
      cardEdge: Color(0xFFD9C7B2),
      ink: Color(0xFF9A5F2E),
      pillBg: Color(0xFFEFE8DD),
      pillText: Color(0xFF6B6564),
      bar: Color(0xFFB9AC9C),
      icon: LucideIcons.circle,
      glow: Color.fromARGB(255, 190, 170, 140),
    ),
    ReferralTierKey.spesial => const TierStyle(
      cardBg: Color(0xFFE3F3F8),
      cardEdge: Color(0xFFB9D8E2),
      ink: Color(0xFF2F7FA0),
      pillBg: Color(0xFFDDEBFF),
      pillText: Color(0xFF2F5AA8),
      bar: Color(0xFF5D86D6),
      icon: LucideIcons.diamond,
      glow: Color.fromARGB(255, 93, 134, 214),
    ),
    ReferralTierKey.langka => const TierStyle(
      cardBg: Color(0xFFECE6F5),
      cardEdge: Color(0xFFC9C0DC),
      ink: Color(0xFF5E4A9A),
      pillBg: Color(0xFFEEE3FF),
      pillText: Color(0xFF6B3FA8),
      bar: Color(0xFF9B6BD0),
      icon: LucideIcons.star,
      glow: Color.fromARGB(255, 155, 107, 208),
    ),
    ReferralTierKey.jackpot => const TierStyle(
      cardBg: Color(0xFFFFF6CF),
      cardEdge: Color(0xFFE8D79A),
      // Darker than the design's #C98A12 (2.7:1 on the card) for legibility.
      ink: Color(0xFF8A5A00),
      pillBg: Color(0xFFFDF1D8),
      pillText: Color(0xFF8A5A00),
      bar: Color(0xFFE0A12A),
      icon: LucideIcons.crown,
      glow: Color.fromARGB(255, 232, 166, 32),
    ),
  };
}

const referralImageDir = 'assets/images/referral';

String tierThumb(ReferralTierKey key) =>
    '$referralImageDir/kartu-hadiah-${key.name}.webp';

String characterArt(String character) =>
    '$referralImageDir/kartu-polos/ilustrasi-coretan-$character.webp';

String tierCharacterCard(ReferralTierKey key, String character) =>
    '$referralImageDir/kartu-hadiah/kartu-hadiah-${key.name}-$character.webp';

/// Patrick Hand, the hand-lettered face on cards and share images.
TextStyle handStyle(Color color, {double size = 18}) =>
    GoogleFonts.patrickHand(fontSize: size, height: 1.1, color: color);

/// "Pikachu" from "pikachu".
String characterName(String key) =>
    key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

/// "70" or "2,5" — odds come as SQL numeric.
String formatOdds(num odds) => odds == odds.roundToDouble()
    ? odds.toInt().toString()
    : odds.toString().replaceAll('.', ',');

class TierPill extends StatelessWidget {
  const TierPill(this.tier, {super.key});

  final ReferralTierKey tier;

  @override
  Widget build(BuildContext context) {
    final s = TierStyle.of(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: s.pillBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 9, color: s.pillText),
          const SizedBox(width: 3),
          Text(
            tier.label.toUpperCase(),
            style: GoogleFonts.urbanist(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.72,
              color: s.pillText,
            ),
          ),
        ],
      ),
    );
  }
}

/// One tier per row: thumbnail, amount, pill, odds bar, percent. Shared by
/// the dashboard's "Isi Pack Hadiah" and the pack screen's odds sheet.
class TierOddsRow extends StatelessWidget {
  const TierOddsRow(this.tier, {super.key, this.showPool = false, this.dark});

  final ReferralTier tier;
  final bool showPool;

  /// Text colour; defaults to the theme's.
  final Color? dark;

  @override
  Widget build(BuildContext context) {
    final s = TierStyle.of(tier.key);
    final text = dark ?? Theme.of(context).colorScheme.onSurface;
    final muted = text.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            height: 60,
            child: showPool && tier.pool.isNotEmpty
                ? _Fan(tier: tier)
                : Image.asset(
                    tierThumb(tier.key),
                    fit: BoxFit.contain,
                    cacheHeight: (60 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    excludeFromSemantics: true,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wraps the pill under the amount at large text sizes.
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      formatRupiah(tier.amount),
                      style: TextStyle(
                        fontFamily: 'CalSans',
                        fontSize: 17,
                        color: text,
                      ),
                    ),
                    TierPill(tier.key),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (tier.odds / 100).clamp(0, 1).toDouble(),
                    minHeight: 6,
                    color: s.bar,
                    backgroundColor:
                        dark == null &&
                            Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).dividerColor
                        : ReferralColors.oddsTrack,
                  ),
                ),
                if (showPool) ...[
                  const SizedBox(height: 4),
                  Text(
                    tier.pool.map(characterName).join(', '),
                    style: GoogleFonts.urbanist(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${formatOdds(tier.odds)}%',
            style: GoogleFonts.urbanist(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Up to 3 of the tier's cards fanned out (03 §5).
class _Fan extends StatelessWidget {
  const _Fan({required this.tier});

  final ReferralTier tier;

  @override
  Widget build(BuildContext context) {
    final pool = tier.pool.take(3).toList();
    const angles = {
      1: [0.0],
      2: [-9.0, 9.0],
      3: [-13.0, 0.0, 13.0],
    };
    final a = angles[pool.length]!;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        for (var i = 0; i < pool.length; i++)
          Transform.rotate(
            angle: a[i] * 3.1415926 / 180,
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              tierCharacterCard(tier.key, pool[i]),
              height: 56,
              cacheHeight: (56 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) =>
                  Image.asset(tierThumb(tier.key), height: 56),
            ),
          ),
      ],
    );
  }
}
