import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/models/bid_proposal_model.dart';
import '../repository/models/listing_offer_model.dart';
import '../repository/proposals_repository.dart';

final proposalsRepositoryProvider = Provider((ref) => ProposalsRepository());

final myOffersProvider = FutureProvider<List<ListingOfferModel>>((ref) {
  return ref.read(proposalsRepositoryProvider).fetchMyOffers();
});

final receivedProposalsProvider = FutureProvider<List<BidProposalModel>>((ref) {
  return ref.read(proposalsRepositoryProvider).fetchReceivedProposals();
});
