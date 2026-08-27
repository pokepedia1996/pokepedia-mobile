import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/bid_proposal_model.dart';
import '../repository/models/listing_offer_model.dart';
import '../usecase/proposals_notifier.dart';

/// Ports `app/proposals/page.tsx` — negotiated offers on ask listings
/// (`listing_offers`) and bid-fulfillment proposals sellers send for the
/// buyer's WTB bids (`bid_proposals`).
class ProposalsPage extends ConsumerStatefulWidget {
  const ProposalsPage({super.key});

  @override
  ConsumerState<ProposalsPage> createState() => _ProposalsPageState();
}

class _ProposalsPageState extends ConsumerState<ProposalsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TransparentAppBar(
        bottom: TabBar(
          controller: _tabController,
          labelColor: context.appColors.primary,
          unselectedLabelColor: context.mutedForeground,
          indicatorColor: context.appColors.primary,
          tabs: const [
            Tab(text: 'Penawaran Saya'),
            Tab(text: 'Proposal Diterima'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabController,
          children: const [_OffersTab(), _ReceivedProposalsTab()],
        ),
      ),
    );
  }
}

Color _offerStatusColor(BuildContext context, OfferStatus status) {
  final semantic = context.appSemantic;
  final colors = context.appColors;
  switch (status) {
    case OfferStatus.pending:
      return semantic.condMp;
    case OfferStatus.accepted:
      return semantic.success;
    case OfferStatus.rejected:
      return colors.error;
    case OfferStatus.expired:
    case OfferStatus.withdrawn:
      return context.mutedForeground;
  }
}

Color _bidProposalStatusColor(BuildContext context, BidProposalStatus status) {
  final semantic = context.appSemantic;
  final colors = context.appColors;
  switch (status) {
    case BidProposalStatus.pending:
      return semantic.condMp;
    case BidProposalStatus.accepted:
      return semantic.success;
    case BidProposalStatus.rejected:
      return colors.error;
    case BidProposalStatus.expired:
    case BidProposalStatus.withdrawn:
      return context.mutedForeground;
  }
}

class _OffersTab extends ConsumerWidget {
  const _OffersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myOffersProvider);
    return async.when(
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.local_offer_outlined,
            title: 'Belum ada penawaran terkirim',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _OfferTile(offer: items[i]),
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat penawaran')),
    );
  }
}

class _OfferTile extends ConsumerStatefulWidget {
  const _OfferTile({required this.offer});

  final ListingOfferModel offer;

  @override
  ConsumerState<_OfferTile> createState() => _OfferTileState();
}

class _OfferTileState extends ConsumerState<_OfferTile> {
  bool _busy = false;

  ListingOfferModel get offer => widget.offer;

  /// Runs one of the offer RPCs, then refreshes the list. [action] answers
  /// null on success or a ready-to-show message on failure.
  Future<void> _run(Future<String?> Function() action, String success) async {
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(error ?? success)));
    if (error == null) ref.invalidate(myOffersProvider);
  }

  Future<void> _counter() async {
    final price = await showCounterPriceDialog(
      context,
      title: 'Tawar balik',
      initialPrice: offer.currentPrice,
    );
    if (price == null || !mounted) return;
    await _run(
      () => ref
          .read(proposalsRepositoryProvider)
          .counterOffer(offerSlug: offer.slug, price: price),
      'Tawaran balik terkirim',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // The buyer can only act when it's their turn: the seller countered and
    // the offer is still open.
    final awaitingBuyer =
        offer.status == OfferStatus.pending &&
        offer.lastActor == OfferActor.seller;
    final canWithdraw =
        offer.status == OfferStatus.pending &&
        offer.lastActor == OfferActor.buyer;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ),
              StatusPill(
                label: offer.status.label,
                color: _offerStatusColor(context, offer.status),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            offer.storeName,
            style: AppTypography.caption(context.mutedForeground),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                formatRupiah(offer.currentPrice),
                style: AppTypography.bodySemibold(colors.onSurface),
              ),
              if (offer.currentPrice != offer.listingPrice) ...[
                const SizedBox(width: 6),
                Text(
                  formatRupiah(offer.listingPrice),
                  style: AppTypography.caption(
                    context.mutedForeground,
                  ).copyWith(decoration: TextDecoration.lineThrough),
                ),
              ],
              const Spacer(),
              Text(
                formatRelativeId(offer.createdAt),
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
          if (offer.isCountered) ...[
            const SizedBox(height: 6),
            Text(
              offer.lastActor == OfferActor.seller
                  ? 'Penjual memberi tawaran balik — menunggu responsmu'
                  : 'Menunggu respons penjual',
              style: AppTypography.caption(context.appColors.primary),
            ),
          ],
          if (awaitingBuyer) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => ref
                                .read(proposalsRepositoryProvider)
                                .acceptOffer(offer.slug),
                            'Penawaran diterima — lanjutkan pembayaran',
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.appSemantic.success,
                      minimumSize: const Size(0, 38),
                    ),
                    child: const Text('Terima'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _counter,
                    child: const Text('Tawar balik'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Tolak',
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => ref
                              .read(proposalsRepositoryProvider)
                              .rejectOffer(offerSlug: offer.slug),
                          'Penawaran ditolak',
                        ),
                  icon: Icon(Icons.close, color: colors.error, size: 20),
                ),
              ],
            ),
          ] else if (canWithdraw) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => ref
                            .read(proposalsRepositoryProvider)
                            .withdrawOffer(offer.slug),
                        'Penawaran ditarik',
                      ),
                child: Text(
                  'Tarik penawaran',
                  style: AppTypography.bodySmSemibold(colors.error),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared price prompt for countering an offer.
Future<int?> showCounterPriceDialog(
  BuildContext context, {
  required String title,
  required int initialPrice,
}) {
  final controller = TextEditingController(text: '$initialPrice');
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(prefixText: 'Rp ', hintText: '0'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            final value = int.tryParse(controller.text) ?? 0;
            Navigator.of(context).pop(value > 0 ? value : null);
          },
          child: const Text('Kirim'),
        ),
      ],
    ),
  );
}

class _ReceivedProposalsTab extends ConsumerWidget {
  const _ReceivedProposalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receivedProposalsProvider);
    return async.when(
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Belum ada proposal diterima',
            description:
                'Proposal muncul saat penjual menawarkan kartu untuk bid (WTB) aktifmu.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _BidProposalTile(proposal: items[i]),
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat proposal')),
    );
  }
}

class _BidProposalTile extends ConsumerStatefulWidget {
  const _BidProposalTile({required this.proposal});

  final BidProposalModel proposal;

  @override
  ConsumerState<_BidProposalTile> createState() => _BidProposalTileState();
}

class _BidProposalTileState extends ConsumerState<_BidProposalTile> {
  bool _busy = false;

  BidProposalModel get proposal => widget.proposal;

  Future<void> _run(Future<String?> Function() action, String success) async {
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(error ?? success)));
    if (error == null) ref.invalidate(receivedProposalsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pending = proposal.status == BidProposalStatus.pending;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  proposal.card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
              ),
              StatusPill(
                label: proposal.status.label,
                color: _bidProposalStatusColor(context, proposal.status),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${proposal.sellerStoreName} · ×${proposal.proposedQuantity}',
            style: AppTypography.caption(context.mutedForeground),
          ),
          if (proposal.message != null) ...[
            const SizedBox(height: 6),
            Text(
              proposal.message!,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            formatRelativeId(proposal.createdAt),
            style: AppTypography.caption(context.mutedForeground),
          ),
          if (pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => ref
                                .read(proposalsRepositoryProvider)
                                .acceptBidProposal(proposal.slug),
                            'Proposal diterima — lanjutkan pembayaran',
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.appSemantic.success,
                      minimumSize: const Size(0, 38),
                    ),
                    child: const Text('Terima'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => ref
                                .read(proposalsRepositoryProvider)
                                .rejectBidProposal(proposalSlug: proposal.slug),
                            'Proposal ditolak',
                          ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
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
