import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/proposal_card_group.dart';
import '../usecase/proposals_notifier.dart';

/// Ports `app/proposals/page.tsx` — negotiated offers on ask listings
/// (`listing_offers`) and bid-fulfillment proposals sellers send for the
/// buyer's WTB bids (`bid_proposals`).
class ProposalsPage extends ConsumerStatefulWidget {
  const ProposalsPage({super.key, this.initialFilter = ProposalFeedFilter.all});

  /// Which status chip to preselect. The market banner uses this to land on
  /// whatever its subtitle just described.
  final ProposalFeedFilter initialFilter;

  @override
  ConsumerState<ProposalsPage> createState() => _ProposalsPageState();
}

class _ProposalsPageState extends ConsumerState<ProposalsPage> {
  @override
  void initState() {
    super.initState();
    // After the first frame: setting provider state during build throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(proposalFeedFilterProvider.notifier).state =
          widget.initialFilter;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: TransparentAppBar(),
      body: AppBarOverlayBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Proposal Saya',
                    style: AppTypography.h1(colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Aktivitas bid dan proposal kamu, dikelompokkan per kartu.',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Expanded(child: _CardFeedTab()),
          ],
        ),
      ),
    );
  }
}

/// Ports the filter group in `card-feed-list.tsx`: one muted track with the
/// options inside it, the active one raised onto the card colour.
///
/// A row of separate pills, which is what this was, makes each option look
/// like its own control — a set of things you might turn on. A track makes
/// them one control with one answer, which is what a filter is.
class _FilterTrack extends StatelessWidget {
  const _FilterTrack({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        // Full width, like the block-level `div` web draws it as. The
        // options still start at the left inside it rather than being
        // stretched to fill — a filter whose widths move as the counts
        // change is harder to aim at than one that stays put.
        width: double.infinity,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.appColors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(AppRadius.md);

    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          // `bg-card shadow-sm` for the one that's on; nothing at all for
          // the rest, so the track shows through.
          color: selected ? Theme.of(context).cardColor : Colors.transparent,
          borderRadius: radius,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: selected
              ? AppTypography.captionSemibold(colors.onSurface)
              : AppTypography.caption(context.mutedForeground),
        ),
      ),
    );
  }
}

class _CardFeedTab extends ConsumerWidget {
  const _CardFeedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(proposalCardFeedProvider);
    final filter = ref.watch(proposalFeedFilterProvider);

    return async.when(
      loading: () => const PikachuLoader(),
      error: (_, __) => Center(
        child: Text(
          'Gagal memuat proposal',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.inbox,
            title: 'Belum ada aktivitas',
            description:
                'Pasang bid (WTB) atau kirim proposal untuk mulai bernegosiasi.',
          );
        }

        final visible = groups.where(filter.matches).toList();

        return Column(
          children: [
            // Web states the size of the feed above the filter, so the
            // count on "Semua" has something to be a share of.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${groups.length} kartu dengan aktivitas',
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
              ),
            ),
            _FilterTrack(
              children: [
                for (final option in ProposalFeedFilter.values)
                  // Web drops a chip with nothing behind it; "Semua"
                  // always stands so there is a way back.
                  if (option == ProposalFeedFilter.all ||
                      groups.any(option.matches))
                    _FilterChip(
                      label:
                          '${option.label} '
                          '(${groups.where(option.matches).length})',
                      selected: filter == option,
                      onTap: () =>
                          ref.read(proposalFeedFilterProvider.notifier).state =
                              option,
                    ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: visible.isEmpty
                  ? const EmptyState(
                      icon: LucideIcons.filterX,
                      title: 'Tidak ada kartu untuk filter ini',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(myBidsProvider);
                        ref.invalidate(sentProposalsProvider);
                        await ref.read(proposalCardFeedProvider.future);
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) =>
                            _CardGroupRow(group: visible[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CardGroupRow extends StatelessWidget {
  const _CardGroupRow({required this.group});

  final ProposalCardGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final card = group.card;
    final breakdown = group.statusBreakdown;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => context.push(Routes.cardProposals(card.id)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              child: CardArt(
                imageUrl: card.imageUrl,
                borderRadius: AppRadius.sm,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  Text(
                    '${card.expansionCode.toUpperCase()} #'
                    '${card.collectorNumber}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  if (group.subtitle.isNotEmpty)
                    Text(
                      group.subtitle,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  if (breakdown.isNotEmpty)
                    Text(
                      breakdown,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  if (group.earliestExpiry != null)
                    Text(
                      'Berakhir ${formatShortDateId(group.earliestExpiry!)}',
                      style: AppTypography.caption(context.appSemantic.condMp),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (group.receivedPending > 0)
                  StatusPill(
                    label: '${group.receivedPending} menunggu',
                    color: context.appSemantic.condMp,
                  ),
                if (group.sentPending > 0) ...[
                  if (group.receivedPending > 0) const SizedBox(height: 4),
                  StatusPill(
                    label: '${group.sentPending} terkirim',
                    color: context.mutedForeground,
                  ),
                ],
              ],
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}
