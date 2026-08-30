import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/models/bid_proposal_model.dart';
import '../repository/models/listing_offer_model.dart';
import '../repository/models/my_bid.dart';
import '../repository/models/proposal_card_group.dart';
import '../repository/models/sent_proposal.dart';
import '../repository/models/proposals_summary.dart';
import '../repository/proposals_repository.dart';

final proposalsRepositoryProvider = Provider((ref) {
  return ProposalsRepository(ref.read(supabaseClientProvider));
});

/// Counts behind the market page's proposal banner. Signed out means no
/// banner at all, matching web's early return.
final proposalsSummaryProvider = FutureProvider<ProposalsSummary>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const ProposalsSummary());
  return ref.read(proposalsRepositoryProvider).fetchSummary();
});

/// Everything the per-card Proposal page shows, filtered out of the lists
/// the feed already loaded.
///
/// Deliberately not three new card-scoped queries: the page is reached from
/// the feed, whose data is in hand, and re-fetching risks the drill-down
/// disagreeing with the row that led to it.
typedef CardProposalData = ({
  List<MyBidModel> bids,
  List<BidProposalModel> received,
  List<SentProposalModel> sent,
});

final cardProposalsProvider = FutureProvider.family<CardProposalData, int>((
  ref,
  cardId,
) async {
  final bids = await ref.watch(myBidsProvider.future);
  final received = await ref.watch(receivedProposalsProvider.future);
  final sent = await ref.watch(sentProposalsProvider.future);
  return (
    bids: bids.where((b) => b.card.id == cardId).toList(),
    received: received.where((p) => p.card.id == cardId).toList(),
    sent: sent.where((p) => p.card.id == cardId).toList(),
  );
});

/// Which status filter the card feed is showing.
final proposalFeedFilterProvider = StateProvider<ProposalFeedFilter>(
  (ref) => ProposalFeedFilter.all,
);

/// The card-grouped feed — web's default Proposal view. Composed from the
/// bid and sent-proposal providers rather than its own query, so a refresh
/// of either flows through and the numbers can't disagree.
final proposalCardFeedProvider = FutureProvider<List<ProposalCardGroup>>((
  ref,
) async {
  final bids = await ref.watch(myBidsProvider.future);
  final sent = await ref.watch(sentProposalsProvider.future);
  return groupProposalsByCard(bids: bids, sent: sent);
});

/// Proposals this user sent as a seller on other people's WTB bids.
final sentProposalsProvider = FutureProvider<List<SentProposalModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(proposalsRepositoryProvider).fetchSentProposals();
});

/// The user's own open WTB bids — what the market banner's "N bid aktif"
/// refers to.
final myBidsProvider = FutureProvider<List<MyBidModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(proposalsRepositoryProvider).fetchMyBids();
});

/// Offers this user sent on other sellers' asks.
final myOffersProvider = FutureProvider<List<ListingOfferModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(proposalsRepositoryProvider).fetchMyOffers();
});

/// The viewer's own live offer on one listing, keyed by `listings.slug`.
///
/// Null when there is none. Drives the listing page's Tawar button: with a
/// live offer already running, `submit_offer` refuses a second one
/// (`offer_already_pending`), so the button has to lead to the existing
/// offer rather than into a rejection.
///
/// Derived from [myOffersProvider] rather than queried per listing — the
/// buyer's whole offer list is one small read the app already makes.
final myOfferOnListingProvider =
    Provider.family<AsyncValue<ListingOfferModel?>, String>((ref, listingSlug) {
      if (listingSlug.isEmpty) return const AsyncValue.data(null);

      return ref.watch(myOffersProvider).whenData((offers) {
        for (final offer in offers) {
          // Blank on both sides is not a match: a row predating the embed
          // would otherwise attach to whichever listing failed to carry a
          // slug, and claim the buyer had already offered on it.
          if (offer.listingSlug.isEmpty || offer.listingSlug != listingSlug) {
            continue;
          }
          // Only a live one blocks a new offer. A rejected or expired offer
          // is history, and the buyer is free to try again.
          if (offer.status == OfferStatus.pending ||
              offer.status == OfferStatus.accepted) {
            return offer;
          }
        }
        return null;
      });
    });

/// Proposals sellers sent against this user's own WTB bids.
final receivedProposalsProvider = FutureProvider<List<BidProposalModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(proposalsRepositoryProvider).fetchBidProposals();
});
