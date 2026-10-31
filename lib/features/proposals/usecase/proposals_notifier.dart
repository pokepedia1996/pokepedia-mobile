import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../moderation/usecase/moderation_notifier.dart';
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
  return ProposalsRepository(
    ref.read(supabaseClientProvider),
    blockedIds: () => ref.read(blockedPairIdsProvider.future),
  );
});

/// Counts behind the market page's proposal banner. Signed out means no
/// banner at all, matching web's early return.
final proposalsSummaryProvider = FutureProvider<ProposalsSummary>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const ProposalsSummary());
  return ref.read(proposalsRepositoryProvider).fetchSummary();
});

/// Everything the per-card Proposal page shows, filtered out of the user's
/// full bid and proposal lists.
///
/// The feed no longer holds those lists — it loads a batch at a time — so
/// opening a card reads them whole. Card-scoped queries would be lighter
/// for an account with a long history.
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

/// Rows of each kind the feed asks for at a time: two of the repository's
/// 50-row pages. The newest activity comes first, so this is what the feed
/// opens on; older activity loads on request.
const proposalFeedBatch = 100;

/// What the Proposal page has loaded so far, grouped by card.
class ProposalFeed {
  const ProposalFeed({
    required this.groups,
    required this.hasMore,
    this.loadingMore = false,
  });

  final List<ProposalCardGroup> groups;

  /// Older bids or sent proposals are still on the server.
  final bool hasMore;
  final bool loadingMore;
}

/// The card-grouped feed — web's default Proposal view — loaded a batch at a
/// time rather than walked to the end. An account with years of bids and
/// proposals used to pull every row and every received proposal before the
/// page could draw anything; now it reads the newest [proposalFeedBatch] of
/// each and fetches older ones from [ProposalFeedNotifier.loadMore].
///
/// A card whose activity spans the boundary shows what has loaded so far,
/// and its counts catch up as older rows arrive.
final proposalCardFeedProvider =
    AsyncNotifierProvider<ProposalFeedNotifier, ProposalFeed>(
      ProposalFeedNotifier.new,
    );

class ProposalFeedNotifier extends AsyncNotifier<ProposalFeed> {
  final _bids = <MyBidModel>[];
  final _sent = <SentProposalModel>[];
  var _bidsHasMore = true;
  var _sentHasMore = true;

  @override
  Future<ProposalFeed> build() async {
    _bids.clear();
    _sent.clear();
    _bidsHasMore = true;
    _sentHasMore = true;
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const ProposalFeed(groups: [], hasMore: false);
    await _fetchNext();
    return _feed();
  }

  /// The next batch of whichever lists still have more. A failure leaves
  /// what is on screen and keeps the button for another try.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
      ProposalFeed(groups: current.groups, hasMore: true, loadingMore: true),
    );
    try {
      await _fetchNext();
    } catch (_) {
      // Swallowed: the rows already loaded stay, and so does the button.
    }
    state = AsyncData(_feed());
  }

  Future<void> _fetchNext() async {
    final repo = ref.read(proposalsRepositoryProvider);
    final (bids, sent) = await (
      _bidsHasMore
          ? repo.fetchMyBidsPage(offset: _bids.length, limit: proposalFeedBatch)
          : Future.value((rows: const <MyBidModel>[], hasMore: false)),
      _sentHasMore
          ? repo.fetchSentProposalsPage(
              offset: _sent.length,
              limit: proposalFeedBatch,
            )
          : Future.value((rows: const <SentProposalModel>[], hasMore: false)),
    ).wait;
    _bids.addAll(bids.rows);
    _sent.addAll(sent.rows);
    _bidsHasMore = bids.hasMore;
    _sentHasMore = sent.hasMore;
  }

  ProposalFeed _feed() => ProposalFeed(
    groups: groupProposalsByCard(bids: _bids, sent: _sent),
    hasMore: _bidsHasMore || _sentHasMore,
  );
}

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
