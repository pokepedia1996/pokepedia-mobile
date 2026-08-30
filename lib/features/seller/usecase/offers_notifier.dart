import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/models/listing_offer.dart';
import '../repository/offers_repository.dart';

/// Every offer made to this seller. The per-listing screen and the product
/// list's badges both read from this one fetch — the badge counts need the
/// whole set anyway, so scoping the query per listing would cost a round
/// trip per row to answer a question one query already answers.
final receivedOffersProvider = FutureProvider<List<ListingOffer>>(
  (ref) => ref.read(offersRepositoryProvider).fetchReceivedOffers(),
);

/// The offers on one listing, keyed by `listings.slug`.
final listingOffersProvider =
    Provider.family<AsyncValue<List<ListingOffer>>, String>((ref, slug) {
      return ref
          .watch(receivedOffersProvider)
          .whenData(
            (offers) => [
              for (final offer in offers)
                if (offer.listingSlug == slug) offer,
            ],
          );
    });

/// Badge counts per listing slug. Empty while loading rather than an
/// [AsyncValue]: a listing row with no badge yet is the same thing a
/// listing with no offers looks like, and it needs no spinner.
final offerCountsProvider = Provider<Map<String, OfferCount>>((ref) {
  final offers = ref.watch(receivedOffersProvider).valueOrNull;
  return offers == null ? const {} : buildOfferCounts(offers);
});
