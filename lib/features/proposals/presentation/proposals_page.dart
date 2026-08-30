import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      appBar: TransparentAppBar(
        actions: [
          // Listing offers are a different object from proposals, and web
          // keeps them elsewhere entirely — the seller's offers list and
          // inside chat. The app has no chat-side offer UI, so this is the
          // only way to reach them.
          IconButton(
            tooltip: 'Penawaran Saya',
            icon: const Icon(Icons.local_offer_outlined, size: 20),
            onPressed: () => context.push(Routes.offers),
          ),
        ],
      ),
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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? colors.primary : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: selected
              ? AppTypography.captionSemibold(colors.onPrimary)
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
            icon: Icons.inbox_outlined,
            title: 'Belum ada aktivitas',
            description:
                'Pasang bid (WTB) atau kirim proposal untuk mulai bernegosiasi.',
          );
        }

        final visible = groups.where(filter.matches).toList();

        return Column(
          children: [
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final option in ProposalFeedFilter.values)
                    // Web drops a chip with nothing behind it; "Semua"
                    // always stands so there is a way back.
                    if (option == ProposalFeedFilter.all ||
                        groups.any(option.matches)) ...[
                      _FilterChip(
                        label:
                            '${option.label} '
                            '(${groups.where(option.matches).length})',
                        selected: filter == option,
                        onTap: () =>
                            ref
                                    .read(proposalFeedFilterProvider.notifier)
                                    .state =
                                option,
                      ),
                      const SizedBox(width: 6),
                    ],
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const EmptyState(
                      icon: Icons.filter_list_off,
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
            Icon(Icons.chevron_right, size: 18, color: context.mutedForeground),
          ],
        ),
      ),
    );
  }
}
