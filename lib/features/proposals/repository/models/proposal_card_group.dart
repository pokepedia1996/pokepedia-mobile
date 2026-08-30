import '../../../../shared/models/card_model.dart';
import 'bid_proposal_model.dart';
import 'my_bid.dart';
import 'sent_proposal.dart';

/// Ports `CardFeedList`'s `FeedFilter`.
enum ProposalFeedFilter {
  all('Semua'),
  needsAction('Perlu aksi'),
  waiting('Menunggu'),
  accepted('Diterima'),
  done('Selesai');

  const ProposalFeedFilter(this.label);

  final String label;

  /// Ports `matchesFilter`. Note what each one keys off: "perlu aksi" is
  /// proposals *received* (they need your answer), while "menunggu" is ones
  /// you *sent* and are waiting on — the two are not the same queue.
  bool matches(ProposalCardGroup group) => switch (this) {
    ProposalFeedFilter.all => true,
    ProposalFeedFilter.needsAction => group.receivedPending > 0,
    ProposalFeedFilter.waiting => group.sentPending > 0,
    ProposalFeedFilter.accepted =>
      (group.sentByStatus[BidProposalStatus.accepted] ?? 0) > 0,
    ProposalFeedFilter.done => group.sentSettled > 0,
  };
}

/// Every bid and proposal for one card, which is how web's Proposal page
/// organises the feed — a collector thinks "what's happening with this
/// card", not "what's in my sent folder".
class ProposalCardGroup {
  ProposalCardGroup({required this.card});

  final CardModel card;

  /// This user's own open WTB bids for the card.
  int myBidsCount = 0;

  /// Proposals sellers made on those bids.
  int receivedPending = 0;
  int receivedTotal = 0;

  /// Proposals this user sent as a seller for the card.
  int sentPending = 0;
  int sentTotal = 0;
  final Map<BidProposalStatus, int> sentByStatus = {};

  /// Soonest deadline among the sent proposals still pending — the one worth
  /// warning about.
  DateTime? earliestExpiry;

  /// Newest activity of any kind, which orders the feed.
  DateTime? lastActivityAt;

  /// Sent proposals that are over: rejected, expired or withdrawn.
  int get sentSettled =>
      (sentByStatus[BidProposalStatus.rejected] ?? 0) +
      (sentByStatus[BidProposalStatus.expired] ?? 0) +
      (sentByStatus[BidProposalStatus.withdrawn] ?? 0);

  /// Ports the row's `sublabels`.
  String get subtitle => [
    if (myBidsCount > 0) '$myBidsCount bid aktif',
    if (sentTotal > 0) '$sentTotal proposal dikirim',
  ].join(' · ');

  /// Ports `STATUS_BREAKDOWN_ORDER` — the per-status tally under the row,
  /// in web's order, skipping statuses with nothing in them.
  String get statusBreakdown {
    const order = [
      BidProposalStatus.pending,
      BidProposalStatus.accepted,
      BidProposalStatus.rejected,
      BidProposalStatus.expired,
      BidProposalStatus.withdrawn,
    ];
    const labels = {
      BidProposalStatus.pending: 'menunggu',
      BidProposalStatus.accepted: 'diterima',
      BidProposalStatus.rejected: 'ditolak',
      BidProposalStatus.expired: 'kadaluwarsa',
      BidProposalStatus.withdrawn: 'ditarik',
    };
    return [
      for (final status in order)
        if ((sentByStatus[status] ?? 0) > 0)
          '${sentByStatus[status]} ${labels[status]}',
    ].join(' · ');
  }
}

/// Folds bids and sent proposals into one row per card.
///
/// Ordered by most recent activity, falling back to card id so the result is
/// stable when nothing carries a timestamp — web sorts the same way.
List<ProposalCardGroup> groupProposalsByCard({
  required List<MyBidModel> bids,
  required List<SentProposalModel> sent,
}) {
  final byCard = <int, ProposalCardGroup>{};

  ProposalCardGroup ensure(CardModel card) =>
      byCard.putIfAbsent(card.id, () => ProposalCardGroup(card: card));

  DateTime? newest(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  for (final bid in bids) {
    final group = ensure(bid.card);
    group.myBidsCount += 1;
    group.receivedPending += bid.pendingProposals;
    group.receivedTotal += bid.totalProposals;
    group.lastActivityAt = newest(
      group.lastActivityAt,
      newest(bid.createdAt, bid.latestProposalAt),
    );
  }

  for (final proposal in sent) {
    final group = ensure(proposal.card);
    group.sentTotal += 1;
    group.sentByStatus[proposal.status] =
        (group.sentByStatus[proposal.status] ?? 0) + 1;
    group.lastActivityAt = newest(group.lastActivityAt, proposal.createdAt);

    if (proposal.status == BidProposalStatus.pending) {
      group.sentPending += 1;
      final expiresAt = proposal.expiresAt;
      if (expiresAt != null &&
          (group.earliestExpiry == null ||
              expiresAt.isBefore(group.earliestExpiry!))) {
        group.earliestExpiry = expiresAt;
      }
    }
  }

  final groups = byCard.values.toList();
  groups.sort((a, b) {
    final aAt = a.lastActivityAt;
    final bAt = b.lastActivityAt;
    if (aAt != null && bAt != null) return bAt.compareTo(aAt);
    if (aAt != null) return -1;
    if (bAt != null) return 1;
    return b.card.id.compareTo(a.card.id);
  });
  return groups;
}
