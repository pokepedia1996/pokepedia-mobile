import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/widgets/setup_kit.dart';
import '../../../../shared/models/pack_model.dart';
import '../../../home/usecase/home_notifier.dart';

/// A portfolio with nothing in it: the two ways a first card goes in, and
/// a few sets to start browsing from. Where onboarding's "Catat & pantau
/// koleksi" lands a new account.
class PortfolioEmptyState extends ConsumerWidget {
  const PortfolioEmptyState({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = DesignPalette.of(context);
    final sets = ref.watch(explorePacksProvider).valueOrNull;
    final starters = sets == null ? const <PackModel>[] : starterSets(sets);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(palette: palette),
        // Left out until the catalog answers, and if it doesn't: the hero
        // above already has both ways in.
        if (starters.isNotEmpty) ...[
          const SizedBox(height: 22),
          _StarterSets(sets: starters, palette: palette),
        ],
      ],
    );
  }
}

/// The three sets "Mulai dari set populer" offers: the newest that a
/// collector opens packs of, newest first.
///
/// There is no popularity figure to rank by, so new is the stand-in — it is
/// what people are pulling now. Theme decks and starter decks are left
/// out: a twenty-card deck is not where a binder starts. They have no
/// reliable `product_type` (many are null), so the card count tells them
/// apart.
@visibleForTesting
List<PackModel> starterSets(List<PackModel> newestFirst) => newestFirst
    .where(
      (p) =>
          p.cardCount >= _minStarterCards &&
          !p.productType.toLowerCase().contains('deck'),
    )
    .take(3)
    .toList();

const _minStarterCards = 60;

class _Hero extends StatelessWidget {
  const _Hero({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _CardStack(palette: palette),
          const SizedBox(height: 18),
          Text(
            'Portofoliomu masih kosong',
            textAlign: TextAlign.center,
            style: setupHeading(20, palette.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'Tambah kartu pertamamu sekarang!',
            textAlign: TextAlign.center,
            style: setupText(14, palette.muted, FontWeight.w400, 20 / 14),
          ),
          const SizedBox(height: 18),
          // Equal heights, so the shorter description doesn't leave one
          // tile hanging short of the other.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ActionTile(
                    icon: LucideIcons.scanLine,
                    title: 'Scan kartu',
                    description: 'Arahkan kamera, kartu langsung terbaca',
                    dark: true,
                    palette: palette,
                    onTap: () => context.push(Routes.scan),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionTile(
                    icon: LucideIcons.layers,
                    title: 'Pilih dari set',
                    description: 'Telusuri ekspansi & tap kartumu',
                    dark: false,
                    palette: palette,
                    // Sets are browsed on the Pencarian tab, which
                    // `/expansions` itself redirects to.
                    onTap: () => context.go(Routes.search),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Three blank cards fanned out, the middle one waiting for its first card.
class _CardStack extends StatelessWidget {
  const _CardStack({required this.palette});

  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget blank({
      required double turnDegrees,
      required double left,
      required double top,
    }) {
      return Positioned(
        left: left,
        top: top,
        child: Transform.rotate(
          angle: turnDegrees * math.pi / 180,
          alignment: Alignment.topLeft,
          child: Container(
            width: 62,
            height: 86,
            decoration: BoxDecoration(
              color: palette.chip,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 150,
      height: 112,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          blank(turnDegrees: -12, left: 22, top: 18),
          blank(turnDegrees: 12, left: 72, top: 6),
          Positioned(
            left: 44,
            top: 8,
            child: Container(
              width: 62,
              height: 86,
              decoration: BoxDecoration(
                color: palette.brandSoft,
                border: Border.all(color: palette.brandBorder, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(LucideIcons.plus, size: 24, color: palette.brand),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the two ways in: dark for scanning, the lead action, and quiet
/// for browsing sets.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.dark,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool dark;
  final DesignPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = dark ? palette.ctaForeground : palette.ink;
    return Material(
      color: dark ? palette.ctaBackground : palette.chip,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: dark ? BorderSide.none : BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: dark
                      ? palette.ctaForeground.withValues(alpha: 0.12)
                      : palette.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: foreground),
              ),
              const SizedBox(height: 10),
              Text(title, style: setupText(15, foreground, FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                description,
                style: setupText(
                  12,
                  dark ? foreground.withValues(alpha: 0.7) : palette.muted,
                  FontWeight.w400,
                  16 / 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StarterSets extends StatelessWidget {
  const _StarterSets({required this.sets, required this.palette});

  final List<PackModel> sets;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Mulai dari set populer',
                style: setupHeading(17, palette.ink),
              ),
            ),
            InkWell(
              onTap: () => context.go(Routes.search),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Semua ekspansi',
                  style: setupText(13, palette.brand, FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < sets.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _SetTile(pack: sets[i], palette: palette),
                ),
              ],
              // Fewer than three still sit at a third of the width each.
              for (var i = sets.length; i < 3; i++) ...[
                const SizedBox(width: 8),
                const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SetTile extends StatelessWidget {
  const _SetTile({required this.pack, required this.palette});

  final PackModel pack;
  final DesignPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(Routes.packDetail(pack.slug)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.chip,
                  border: Border.all(color: palette.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  pack.mark,
                  style: setupText(11, palette.ink, FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pack.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: setupText(13, palette.ink, FontWeight.w600),
              ),
              const Spacer(),
              const SizedBox(height: 6),
              Text(
                '${pack.cardCount} kartu',
                style: setupText(11, palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
