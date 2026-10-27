import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/bid_proposal_model.dart';
import '../repository/models/sent_proposal.dart';
import '../usecase/proposals_notifier.dart';
import 'widgets/sent_proposal_card.dart';

/// "Penawaranku" — every "Penuhi Bid" this user has sent as a seller, across
/// all cards, with where each one stands.
///
/// A card's own proposals page already lists what was sent for that card;
/// this is the same list without the card in the way, for a seller who has
/// answered bids on many cards and wants to know which were taken.
class MyProposalsPage extends ConsumerStatefulWidget {
  const MyProposalsPage({super.key});

  @override
  ConsumerState<MyProposalsPage> createState() => _MyProposalsPageState();
}

/// Status chips. Unlike the card page's sent filter this one keeps
/// "Menunggu": across every card, what is still out is the first question.
enum MyProposalsFilter {
  all('Semua', null),
  pending('Menunggu', BidProposalStatus.pending),
  accepted('Diterima', BidProposalStatus.accepted),
  rejected('Ditolak', BidProposalStatus.rejected),
  expired('Kedaluwarsa', BidProposalStatus.expired);

  const MyProposalsFilter(this.label, this.status);

  final String label;
  final BidProposalStatus? status;

  bool matches(SentProposalModel proposal) =>
      status == null || proposal.status == status;
}

class _MyProposalsPageState extends ConsumerState<MyProposalsPage> {
  MyProposalsFilter _filter = MyProposalsFilter.all;

  /// The proposal whose dismiss is in flight, for its row's spinner.
  String? _busySlug;

  @override
  void initState() {
    super.initState();
    // Fresh on arrival: a buyer may have answered since the list was cached,
    // and that answer is the reason to open this page at all.
    Future.microtask(() {
      if (mounted) ref.invalidate(sentProposalsProvider);
    });
  }

  Future<void> _dismiss(SentProposalModel proposal) async {
    setState(() => _busySlug = proposal.slug);
    final error = await ref
        .read(proposalsRepositoryProvider)
        .dismissSentProposal(proposal.slug);
    if (!mounted) return;
    setState(() => _busySlug = null);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(error ?? 'Proposal dihapus dari daftar'),
          persist: false,
        ),
      );
    if (error == null) {
      ref.invalidate(sentProposalsProvider);
      ref.invalidate(proposalsSummaryProvider);
    }
  }

  static const _padding = EdgeInsets.fromLTRB(16, 8, 16, 32);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = ref.watch(sentProposalsProvider);
    final title = [
      Text('Penawaranku', style: AppTypography.h2(colors.onSurface)),
      const SizedBox(height: 2),
      Text(
        'Proposal yang kamu kirim untuk memenuhi bid pembeli.',
        style: AppTypography.caption(context.mutedForeground),
      ),
      const SizedBox(height: 14),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(sentProposalsProvider.future),
          child: async.when(
            data: (sent) => _body(sent, title),
            loading: () => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: _padding,
              children: [
                ...title,
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: PikachuLoader(),
                ),
              ],
            ),
            error: (_, __) => ScrollableEmptyState(
              padding: _padding,
              header: title,
              child: EmptyState(
                icon: LucideIcons.circleAlert,
                title: 'Gagal memuat penawaran',
                action: OutlinedButton(
                  onPressed: () => ref.invalidate(sentProposalsProvider),
                  child: const Text('Coba lagi'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The proposals under [title], or — with none, or none under the filter —
  /// the empty state centred in the room left below.
  Widget _body(List<SentProposalModel> sent, List<Widget> title) {
    if (sent.isEmpty) {
      return ScrollableEmptyState(
        padding: _padding,
        header: title,
        child: const EmptyState(
          icon: LucideIcons.send,
          title: 'Belum ada penawaran',
          description:
              'Tekan "Penuhi Bid" pada buylist pembeli untuk mengirim proposal.',
        ),
      );
    }

    final visible = sent.where(_filter.matches).toList();
    final header = [
      ...title,
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final filter in MyProposalsFilter.values) ...[
              _FilterChip(
                label: '${filter.label} (${sent.where(filter.matches).length})',
                selected: _filter == filter,
                onTap: () => setState(() => _filter = filter),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
    if (visible.isEmpty) {
      return ScrollableEmptyState(
        padding: _padding,
        header: header,
        child: const EmptyState(
          icon: LucideIcons.inbox,
          title: 'Belum ada proposal dengan status ini',
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: _padding,
      children: [
        ...header,
        for (final proposal in visible) ...[
          SentProposalCard(
            proposal: proposal,
            busy: _busySlug == proposal.slug,
            onDismiss: () => _dismiss(proposal),
            // A bid that has closed leaves only a placeholder card, with no
            // page to open.
            onOpenCard: proposal.card.id == unavailableProposalCard.id
                ? null
                : () => context.push(
                    Routes.cardDetail(proposal.card.packSlug, proposal.card.id),
                  ),
          ),
          const SizedBox(height: 10),
        ],
      ],
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
