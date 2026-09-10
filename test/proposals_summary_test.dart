import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/proposals_summary.dart';

void main() {
  group('visibility', () {
    test('hidden for someone with no stake in proposals', () {
      // Web returns null here. An empty inbox card on a browsing buyer's
      // market page is pure noise.
      expect(const ProposalsSummary().isVisible, isFalse);
    });

    test('shown for an active seller even with nothing yet', () {
      // They can receive proposals, so the entry point has to exist.
      expect(const ProposalsSummary(isActiveSeller: true).isVisible, isTrue);
    });

    test('shown to a buyer with open bids', () {
      expect(const ProposalsSummary(bidCount: 2).isVisible, isTrue);
    });

    test('shown on past activity alone', () {
      expect(const ProposalsSummary(sentTotal: 1).isVisible, isTrue);
      expect(const ProposalsSummary(receivedTotal: 1).isVisible, isTrue);
    });
  });

  group('which tab it opens', () {
    test('incoming proposals win — they are the ones needing an answer', () {
      const summary = ProposalsSummary(receivedPending: 1, sentPending: 5);
      expect(summary.destination, ProposalsDestination.received);
    });

    test('then proposals awaiting an answer', () {
      expect(
        const ProposalsSummary(sentPending: 3, bidCount: 9).destination,
        ProposalsDestination.sent,
      );
    });

    test('bids-only lands on the bids tab, not an empty offers tab', () {
      // The bug this guards: the banner said "35 bid aktif" and opened
      // Penawaran Saya, which lists offers — a different object entirely —
      // so the page was empty and the banner looked like it was lying.
      const summary = ProposalsSummary(bidCount: 35);
      expect(summary.subtitle, '35 bid aktif');
      expect(summary.destination, ProposalsDestination.bids);
    });

    test('nothing at all falls back to the default tab', () {
      expect(const ProposalsSummary().destination, ProposalsDestination.sent);
    });
  });

  group('badge', () {
    test('unseen incoming drives the red "baru" badge', () {
      const summary = ProposalsSummary(
        receivedPending: 2,
        receivedPendingUnseen: 1,
      );
      expect(summary.hasNew, isTrue);
      expect(summary.totalPending, 2);
    });

    test('seen-but-pending falls back to the muted count', () {
      const summary = ProposalsSummary(receivedPending: 2, sentPending: 1);
      expect(summary.hasNew, isFalse);
      expect(summary.totalPending, 3);
    });
  });

  group('subtitle ladder', () {
    test('both directions pending', () {
      expect(
        const ProposalsSummary(receivedPending: 2, sentPending: 3).subtitle,
        '2 masuk · 3 menunggu jawaban',
      );
    });

    test('only incoming', () {
      expect(
        const ProposalsSummary(receivedPending: 2).subtitle,
        '2 proposal masuk untuk bid kamu',
      );
    });

    test('only outgoing', () {
      expect(
        const ProposalsSummary(sentPending: 4).subtitle,
        '4 proposal kamu menunggu jawaban',
      );
    });

    test('nothing pending falls back to standing activity', () {
      expect(
        const ProposalsSummary(bidCount: 3, sentTotal: 2).subtitle,
        '3 bid aktif · 2 proposal dikirim',
      );
      expect(const ProposalsSummary(bidCount: 3).subtitle, '3 bid aktif');
    });

    test('an active seller with nothing yet gets the prompt', () {
      expect(
        const ProposalsSummary(isActiveSeller: true).subtitle,
        'Belum ada aktivitas · Pasang bid atau kirim proposal',
      );
    });
  });

  group('unseen counting', () {
    test('the badge clears once proposals are marked seen', () {
      // `mark_bid_proposal_seen` sets seen_at, which drops the row out of
      // receivedPendingUnseen while leaving it pending.
      // receivedTotal counts every received proposal, so it is always at
      // least receivedPending — the summary is built from one pass over the
      // same rows.
      const before = ProposalsSummary(
        receivedTotal: 3,
        receivedPending: 3,
        receivedPendingUnseen: 3,
      );
      const after = ProposalsSummary(
        receivedTotal: 3,
        receivedPending: 3,
        receivedPendingUnseen: 0,
      );

      expect(before.hasNew, isTrue);
      expect(after.hasNew, isFalse);
      // Still pending, so the muted count takes over rather than vanishing.
      expect(after.totalPending, 3);
      expect(after.isVisible, isTrue);
    });
  });
}
