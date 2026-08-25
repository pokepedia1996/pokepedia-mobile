import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/models/bid_proposal_model.dart';
import '../repository/models/listing_offer_model.dart';
import '../repository/proposals_repository.dart';

final proposalsRepositoryProvider = Provider((ref) {
  return ProposalsRepository(ref.read(supabaseClientProvider));
});

/// Offers this user sent on other sellers' asks.
final myOffersProvider = FutureProvider<List<ListingOfferModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(proposalsRepositoryProvider).fetchMyOffers();
});

/// Proposals sellers sent against this user's own WTB bids.
final receivedProposalsProvider = FutureProvider<List<BidProposalModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(proposalsRepositoryProvider).fetchBidProposals();
});
