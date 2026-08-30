import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/bid_proposal_model.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/my_bid.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/proposal_card_group.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/sent_proposal.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

CardModel _card(int id, {String name = 'Charizard ex'}) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: name,
  expansionCode: 'SV2a',
  packSlug: 'sv2a',
  collectorNumber: '201/165',
  rarity: 'SAR',
);

MyBidModel _bid(
  int cardId, {
  int pending = 0,
  int total = 0,
  DateTime? createdAt,
  DateTime? latestProposalAt,
}) => MyBidModel(
  slug: 'bid-$cardId',
  card: _card(cardId),
  price: 100000,
  condition: CardCondition.nm,
  quantity: 1,
  qtyLocked: 0,
  createdAt: createdAt,
  pendingProposals: pending,
  totalProposals: total,
  latestProposalAt: latestProposalAt,
);

SentProposalModel _sent(
  int cardId, {
  BidProposalStatus status = BidProposalStatus.pending,
  DateTime? createdAt,
  DateTime? expiresAt,
}) => SentProposalModel(
  slug: 'sent-$cardId-${status.name}-${expiresAt?.day ?? 0}',
  card: _card(cardId),
  condition: CardCondition.nm,
  proposedQuantity: 1,
  status: status,
  bidPrice: 100000,
  createdAt: createdAt,
  expiresAt: expiresAt,
);

void main() {
  group('grouping', () {
    test('bids and sent proposals for one card land on one row', () {
      final groups = groupProposalsByCard(
        bids: [_bid(7, pending: 2, total: 3)],
        sent: [
          _sent(7),
          _sent(7, status: BidProposalStatus.accepted),
        ],
      );

      expect(groups, hasLength(1));
      final group = groups.single;
      expect(group.myBidsCount, 1);
      expect(group.receivedPending, 2);
      expect(group.receivedTotal, 3);
      expect(group.sentTotal, 2);
      expect(group.sentPending, 1);
    });

    test('different cards stay apart', () {
      final groups = groupProposalsByCard(
        bids: [_bid(7), _bid(8)],
        sent: [_sent(9)],
      );
      expect(groups.map((g) => g.card.id).toSet(), {7, 8, 9});
    });

    test('several bids on one card accumulate', () {
      final groups = groupProposalsByCard(
        bids: [_bid(7, pending: 1, total: 1), _bid(7, pending: 2, total: 4)],
        sent: const [],
      );
      expect(groups.single.myBidsCount, 2);
      expect(groups.single.receivedPending, 3);
      expect(groups.single.receivedTotal, 5);
    });

    test('the soonest deadline among pending sent proposals wins', () {
      final groups = groupProposalsByCard(
        bids: const [],
        sent: [
          _sent(7, expiresAt: DateTime(2026, 9, 20)),
          _sent(7, expiresAt: DateTime(2026, 9, 5)),
          // Settled proposals have no clock running, so they're ignored.
          _sent(
            7,
            status: BidProposalStatus.rejected,
            expiresAt: DateTime(2026, 9, 1),
          ),
        ],
      );
      expect(groups.single.earliestExpiry, DateTime(2026, 9, 5));
    });

    test('newest activity first, whichever side it came from', () {
      final groups = groupProposalsByCard(
        bids: [_bid(7, createdAt: DateTime(2026, 8, 1))],
        sent: [_sent(8, createdAt: DateTime(2026, 8, 20))],
      );
      expect(groups.map((g) => g.card.id), [8, 7]);
    });

    test('a proposal on an old bid lifts that card up the feed', () {
      // The bid is ancient but someone just proposed on it — that is the
      // activity a collector cares about.
      final groups = groupProposalsByCard(
        bids: [
          _bid(
            7,
            createdAt: DateTime(2026, 1, 1),
            latestProposalAt: DateTime(2026, 8, 25),
          ),
        ],
        sent: [_sent(8, createdAt: DateTime(2026, 8, 20))],
      );
      expect(groups.map((g) => g.card.id), [7, 8]);
    });
  });

  group('filters', () {
    ProposalCardGroup groupWith({
      int received = 0,
      int sentPending = 0,
      int accepted = 0,
      int rejected = 0,
    }) {
      return groupProposalsByCard(
        bids: [if (received > 0) _bid(7, pending: received, total: received)],
        sent: [
          for (var i = 0; i < sentPending; i++) _sent(7),
          for (var i = 0; i < accepted; i++)
            _sent(7, status: BidProposalStatus.accepted),
          for (var i = 0; i < rejected; i++)
            _sent(7, status: BidProposalStatus.rejected),
        ],
      ).single;
    }

    test('"Perlu aksi" is proposals received, not ones sent', () {
      // The distinction that matters: received proposals need *your* answer,
      // sent ones are you waiting on someone else.
      final received = groupWith(received: 1);
      final sent = groupWith(sentPending: 1);

      expect(ProposalFeedFilter.needsAction.matches(received), isTrue);
      expect(ProposalFeedFilter.needsAction.matches(sent), isFalse);
      expect(ProposalFeedFilter.waiting.matches(sent), isTrue);
      expect(ProposalFeedFilter.waiting.matches(received), isFalse);
    });

    test('"Diterima" keys off accepted sent proposals', () {
      expect(
        ProposalFeedFilter.accepted.matches(groupWith(accepted: 1)),
        isTrue,
      );
      expect(
        ProposalFeedFilter.accepted.matches(groupWith(sentPending: 1)),
        isFalse,
      );
    });

    test('"Selesai" collects everything that ended without acceptance', () {
      expect(ProposalFeedFilter.done.matches(groupWith(rejected: 2)), isTrue);
      expect(ProposalFeedFilter.done.matches(groupWith(accepted: 1)), isFalse);
    });

    test('"Semua" matches everything', () {
      // A group only exists because something is in it, so "everything" is
      // tested against each kind rather than an empty one.
      expect(ProposalFeedFilter.all.matches(groupWith(received: 1)), isTrue);
      expect(ProposalFeedFilter.all.matches(groupWith(sentPending: 1)), isTrue);
      expect(ProposalFeedFilter.all.matches(groupWith(rejected: 1)), isTrue);
    });
  });

  group('row copy', () {
    test('subtitle names both sides, omitting what is zero', () {
      final both = groupProposalsByCard(
        bids: [_bid(7)],
        sent: [_sent(7), _sent(7)],
      ).single;
      expect(both.subtitle, '1 bid aktif · 2 proposal dikirim');

      final bidsOnly = groupProposalsByCard(
        bids: [_bid(7)],
        sent: const [],
      ).single;
      expect(bidsOnly.subtitle, '1 bid aktif');
    });

    test('status breakdown follows web order and skips empty statuses', () {
      final group = groupProposalsByCard(
        bids: const [],
        sent: [
          _sent(7, status: BidProposalStatus.rejected),
          _sent(7),
          _sent(7, status: BidProposalStatus.accepted),
          _sent(7, status: BidProposalStatus.accepted),
        ],
      ).single;
      expect(group.statusBreakdown, '1 menunggu · 2 diterima · 1 ditolak');
    });
  });
}
