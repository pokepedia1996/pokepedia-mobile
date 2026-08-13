import 'package:flutter/material.dart';
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

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer});

  final ListingOfferModel offer;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
        ],
      ),
    );
  }
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

class _BidProposalTile extends StatelessWidget {
  const _BidProposalTile({required this.proposal});

  final BidProposalModel proposal;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
        ],
      ),
    );
  }
}
