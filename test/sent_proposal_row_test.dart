import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/bid_proposal_model.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/sent_proposal.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The sent list on a card page, against what `sent-proposals-list.tsx`
/// shows: the price asked over the bid it answers, and a clock that stops
/// counting once it has run out.
SentProposalModel _proposal({
  int bidPrice = 12577,
  int? proposedPrice,
  BidProposalStatus status = BidProposalStatus.pending,
  Duration? expiresIn,
}) => SentProposalModel(
  slug: 'p1',
  card: const CardModel(
    id: 1,
    category: CardCategory.pokemon,
    nameId: 'Alakazam',
    expansionCode: 'EX',
    packSlug: 'ex',
    collectorNumber: '001/165',
    rarity: 'Rare',
  ),
  condition: CardCondition.nm,
  proposedQuantity: 1,
  status: status,
  bidPrice: bidPrice,
  proposedPrice: proposedPrice,
  expiresAt: expiresIn == null ? null : DateTime.now().add(expiresIn),
);

void main() {
  test('the price shown is what was asked, not what was bid', () {
    // A counter above the bid is the number the buyer has to answer.
    expect(_proposal(proposedPrice: 20000).effectivePrice, 20000);
    // Accepting the bid as it stands shows the bid.
    expect(_proposal().effectivePrice, 12577);
  });

  test('a settled proposal has no clock left to run', () {
    expect(_proposal(status: BidProposalStatus.accepted).remaining, isNull);
    expect(_proposal(status: BidProposalStatus.expired).remaining, isNull);
  });

  test('a passed deadline reads as spent, not as a countdown', () {
    // `Duration.zero` is what the row draws "Waktu habis" from; before this
    // it formatted as "kurang dari 1 menit" for as long as the row lived.
    final overdue = _proposal(expiresIn: const Duration(seconds: -30));
    expect(overdue.remaining, Duration.zero);
  });

  test('a live deadline still counts down', () {
    final live = _proposal(expiresIn: const Duration(hours: 5));
    expect(live.remaining!.inHours, 4);
  });
}
