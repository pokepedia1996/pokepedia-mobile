import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_condition.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../expansions/usecase/expansions_notifier.dart';
import '../repository/models/bid_proposal_model.dart';
import '../repository/models/my_bid.dart';
import '../repository/models/sent_proposal.dart';
import '../usecase/proposals_notifier.dart';
import 'widgets/bid_edit_sheet.dart';

/// Ports `/proposals/card/[cardId]` — everything happening on one card:
/// your bids for it, the proposals sellers made on those bids, and the
/// proposals you sent on other people's bids for it.
class CardProposalsPage extends ConsumerStatefulWidget {
  const CardProposalsPage({super.key, required this.cardId});

  final int cardId;

  @override
  ConsumerState<CardProposalsPage> createState() => _CardProposalsPageState();
}

/// Ports `SUB_TABS` — the received list's own status filter.
enum _ReceivedFilter {
  all('Semua', null),
  pending('Menunggu', BidProposalStatus.pending),
  accepted('Diterima', BidProposalStatus.accepted),
  rejected('Ditolak', BidProposalStatus.rejected);

  const _ReceivedFilter(this.label, this.status);

  final String label;
  final BidProposalStatus? status;
}

class _CardProposalsPageState extends ConsumerState<CardProposalsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  _ReceivedFilter _receivedFilter = _ReceivedFilter.all;

  /// Slugs already reported read this session, so a rebuild doesn't re-post.
  final _marked = <String>{};
  String? _busySlug;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final async = ref.watch(cardProposalsProvider(widget.cardId));
    final card = ref.watch(cardDetailProvider(widget.cardId)).valueOrNull;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: async.when(
          loading: () => const PikachuLoader(),
          error: (_, __) => Center(
            child: Text(
              'Gagal memuat proposal',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
          data: (data) {
            // Prefer a card off the lists: it is already loaded, so the
            // header paints with the rest instead of a beat later.
            final resolved =
                card ??
                (data.bids.isNotEmpty
                    ? data.bids.first.card
                    : data.received.isNotEmpty
                    ? data.received.first.card
                    : data.sent.isNotEmpty
                    ? data.sent.first.card
                    : null);

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(myBidsProvider);
                ref.invalidate(receivedProposalsProvider);
                ref.invalidate(sentProposalsProvider);
                await ref.read(cardProposalsProvider(widget.cardId).future);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (resolved != null) _CardHeader(card: resolved),
                  const SizedBox(height: 16),
                  Text(
                    'Bid kamu untuk kartu ini',
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 8),
                  if (data.bids.isEmpty)
                    _Placeholder(
                      text: 'Belum ada bid aktif',
                      icon: Icons.gavel_outlined,
                    )
                  else
                    for (final bid in data.bids) ...[
                      _BidRow(
                        bid: bid,
                        busy: _busySlug == bid.slug,
                        onEdit: () => _editBid(bid),
                        onDelete: () => _deleteBid(bid),
                      ),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 16),
                  TabBar(
                    controller: _tabController,
                    labelColor: colors.primary,
                    unselectedLabelColor: context.mutedForeground,
                    indicatorColor: colors.primary,
                    tabs: const [
                      Tab(text: 'Diterima'),
                      Tab(text: 'Dikirim'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_tabController.index == 0) ...[
                    Builder(
                      builder: (_) {
                        _markSeen(data.received);
                        return const SizedBox.shrink();
                      },
                    ),
                    ..._received(data.received),
                  ] else
                    ..._sent(data.sent),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Opening the card is what "seen" means now that this page is where
  /// proposals are read. Runs after the frame so the list paints first.
  void _markSeen(List<BidProposalModel> items) {
    final unseen = items
        .where((p) => p.seenAt == null && !_marked.contains(p.slug))
        .map((p) => p.slug)
        .toList();
    if (unseen.isEmpty) return;
    _marked.addAll(unseen);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(proposalsRepositoryProvider).markProposalsSeen(unseen);
      if (!mounted) return;
      // The market banner counts unseen proposals, so it is now stale.
      ref.invalidate(proposalsSummaryProvider);
    });
  }

  /// Runs a proposal action and refreshes everything that counts it.
  Future<void> _run(
    String slug,
    Future<String?> Function() action,
    String success,
  ) async {
    setState(() => _busySlug = slug);
    final error = await action();
    if (!mounted) return;
    setState(() => _busySlug = null);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(error ?? success), persist: false));
    if (error == null) {
      ref.invalidate(receivedProposalsProvider);
      ref.invalidate(sentProposalsProvider);
      ref.invalidate(myBidsProvider);
      ref.invalidate(proposalsSummaryProvider);
    }
  }

  Future<void> _editBid(MyBidModel bid) async {
    final result = await showBidEditSheet(context, bid: bid);
    if (result == null || !mounted) return;

    await _run(
      bid.slug,
      () => ref
          .read(proposalsRepositoryProvider)
          .updateBid(
            slug: bid.slug,
            price: result.price,
            quantity: result.quantity,
          ),
      'Bid diperbarui',
    );
  }

  Future<void> _deleteBid(MyBidModel bid) {
    return showConfirmDialog(
      context,
      title: 'Hapus bid?',
      description:
          'Bid ${formatRupiah(bid.price)} untuk ${bid.card.name} akan '
          'dibatalkan. Penjual tidak bisa lagi mengirim proposal untuknya.',
      confirmLabel: 'Hapus',
      loadingLabel: 'Menghapus...',
      onConfirm: () => _run(
        bid.slug,
        () => ref.read(proposalsRepositoryProvider).cancelBid(bid.slug),
        'Bid dihapus',
      ),
    );
  }

  List<Widget> _received(List<BidProposalModel> all) {
    final visible = _receivedFilter.status == null
        ? all
        : all.where((p) => p.status == _receivedFilter.status).toList();

    return [
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final filter in _ReceivedFilter.values) ...[
              _Chip(
                label: filter.label,
                selected: _receivedFilter == filter,
                onTap: () => setState(() => _receivedFilter = filter),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      if (visible.isEmpty)
        _Placeholder(
          text: all.isEmpty
              ? 'Belum ada proposal untuk bid kamu'
              : 'Belum ada proposal dengan status ini.',
          icon: Icons.inbox_outlined,
        )
      else
        for (final proposal in visible) ...[
          _ReceivedRow(
            proposal: proposal,
            busy: _busySlug == proposal.slug,
            onAccept: () => _run(
              proposal.slug,
              () => ref
                  .read(proposalsRepositoryProvider)
                  .acceptBidProposal(proposal.slug),
              'Proposal diterima — lanjutkan pembayaran',
            ),
            onReject: () => _run(
              proposal.slug,
              () => ref
                  .read(proposalsRepositoryProvider)
                  .rejectBidProposal(proposalSlug: proposal.slug),
              'Proposal ditolak',
            ),
          ),
          const SizedBox(height: 8),
        ],
    ];
  }

  List<Widget> _sent(List<SentProposalModel> sent) {
    if (sent.isEmpty) {
      return [
        _Placeholder(
          text: 'Kirim proposal pada bid pembeli dari halaman kartu.',
          icon: Icons.send_outlined,
        ),
      ];
    }
    return [
      for (final proposal in sent) ...[
        _SentRow(
          proposal: proposal,
          busy: _busySlug == proposal.slug,
          onDismiss: () => _run(
            proposal.slug,
            () => ref
                .read(proposalsRepositoryProvider)
                .dismissSentProposal(proposal.slug),
            'Proposal dihapus dari daftar',
          ),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.card});

  final CardModel card;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: CardArt(imageUrl: card.imageUrl, borderRadius: AppRadius.sm),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.h3(colors.onSurface),
                ),
                Text(
                  '${card.expansionCode.toUpperCase()} #'
                  '${card.collectorNumber}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ports `BuyerBidsList`'s row.
class _BidRow extends StatelessWidget {
  const _BidRow({
    required this.bid,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final MyBidModel bid;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Web disables both actions once a proposal is waiting, and
    // `update_order_self` / `cancel_order_self` refuse with
    // `bid_has_proposals` regardless — so the row explains rather than
    // offering a button that will bounce.
    final locked = bid.pendingProposals > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatRupiah(bid.price),
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    Text(
                      '${bid.available}x'
                      '${bid.createdAt == null ? "" : " · ${formatRelativeId(bid.createdAt!)}"}',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),
              ),
              // Web's ladder: pending first, then any at all.
              StatusPill(
                label: bid.pendingProposals > 0
                    ? '${bid.pendingProposals} menunggu'
                    : bid.totalProposals > 0
                    ? '${bid.totalProposals} proposal'
                    : 'Belum ada proposal',
                color: bid.pendingProposals > 0
                    ? context.appSemantic.condMp
                    : context.mutedForeground,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (locked)
            Text(
              'Bid ini sudah menerima proposal — tidak bisa diubah atau '
              'dihapus.',
              style: AppTypography.caption(context.mutedForeground),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onDelete,
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('Hapus'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
                      minimumSize: const Size(0, 36),
                      side: BorderSide(
                        color: colors.error.withValues(alpha: 0.4),
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

class _ReceivedRow extends StatelessWidget {
  const _ReceivedRow({
    required this.proposal,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final BidProposalModel proposal;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proposal.sellerStoreName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    Text(
                      '${proposal.condition.label} · '
                      '${proposal.proposedQuantity} pcs',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: proposal.status.label,
                color: switch (proposal.status) {
                  BidProposalStatus.pending => context.appSemantic.condMp,
                  BidProposalStatus.accepted => context.appSemantic.success,
                  BidProposalStatus.rejected => colors.error,
                  _ => context.mutedForeground,
                },
              ),
            ],
          ),
          if (proposal.message != null && proposal.message!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              proposal.message!,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ],
          // Only an open proposal can be answered.
          if (proposal.status == BidProposalStatus.pending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: busy ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.appSemantic.success,
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Terima'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Tolak'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SentRow extends StatelessWidget {
  const _SentRow({
    required this.proposal,
    required this.busy,
    required this.onDismiss,
  });

  final SentProposalModel proposal;
  final bool busy;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bid dari @${proposal.buyerUsername ?? "pembeli"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                Text(
                  '${formatRupiah(proposal.effectivePrice)} · '
                  '${proposal.proposedQuantity} pcs',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
          StatusPill(
            label: proposal.status.label,
            color: switch (proposal.status) {
              BidProposalStatus.pending => context.appSemantic.condMp,
              BidProposalStatus.accepted => context.appSemantic.success,
              BidProposalStatus.rejected => colors.error,
              _ => context.mutedForeground,
            },
          ),
          // `dismiss_bid_proposal` refuses a pending row, so the button only
          // exists once the proposal has settled.
          if (proposal.isDismissible)
            IconButton(
              onPressed: busy ? null : onDismiss,
              visualDensity: VisualDensity.compact,
              tooltip: 'Hapus dari daftar',
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: context.mutedForeground,
                    ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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

/// A section-sized empty state — the page stacks several, so the full
/// [EmptyState] would dominate it.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: context.mutedForeground),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}
