import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/models/pack_model.dart';
import '../../../../shared/widgets/app_network_image.dart';
import '../../usecase/home_notifier.dart';
import 'home_section_header.dart';

/// "Jelajahi Rilis Terbaru": the newest sets in the catalog being browsed,
/// each with how much of it the reader's main collection holds.
class LatestReleasesSection extends ConsumerWidget {
  const LatestReleasesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(latestReleasesProvider).valueOrNull ?? const [];
    if (packs.isEmpty) return const SizedBox.shrink();
    final owned = ref.watch(latestReleaseOwnedProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: HomeSectionHeader(
            title: 'Jelajahi Rilis Terbaru',
            onSeeAll: () => context.go(Routes.search),
          ),
        ),
        const SizedBox(height: 20),
        // Sized to its tallest card rather than a fixed height, so a long
        // name or a larger system text size grows the row instead of
        // overflowing it; the cards then share that height.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Room for the cards' shadow, which a scroll view clips at its
          // edges.
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, pack) in packs.indexed) ...[
                  if (i > 0) const SizedBox(width: 14),
                  ReleaseCard(
                    pack: pack,
                    // Null signed out: no progress drawn, rather than a 0/N
                    // that reads as the reader's own.
                    owned: owned == null ? null : (owned[pack.slug] ?? 0),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One set: its logo, code and name, and the main collection's progress
/// through it.
@visibleForTesting
class ReleaseCard extends StatelessWidget {
  const ReleaseCard({super.key, required this.pack, this.owned});

  final PackModel pack;

  /// Cards of [pack] the main collection holds; null when there is no
  /// collection to measure (signed out).
  final int? owned;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final total = pack.cardCount;
    final held = owned?.clamp(0, total);
    final share = held == null || total == 0 ? 0.0 : held / total;

    return GestureDetector(
      onTap: () => context.push(Routes.packDetail(pack.slug)),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D1C1413),
              offset: Offset(0, 2),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 112,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: palette.chip,
                borderRadius: BorderRadius.circular(10),
              ),
              child: pack.image == null
                  ? null
                  : cachedNetworkImage(
                      pack.image!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
            const SizedBox(height: 10),
            // Two lines' room even for a one-line name, so the progress
            // bars of neighbouring cards line up.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 38),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: palette.chip,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      pack.mark.toUpperCase(),
                      style: GoogleFonts.urbanist(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pack.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.urbanist(
                        fontSize: 14,
                        height: 19 / 14,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Progress sits at the foot, however tall the row has grown.
            const Spacer(),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  held == null ? '$total kartu' : '$held/$total',
                  style: GoogleFonts.urbanist(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                if (held != null)
                  Text(
                    '${(share * 100).floor()}%',
                    style: GoogleFonts.urbanist(
                      fontSize: 11,
                      color: palette.muted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: palette.chip)),
                    FractionallySizedBox(
                      widthFactor: share,
                      heightFactor: 1,
                      child: ColoredBox(color: palette.brand),
                    ),
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
