import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../repository/models/seller_listing.dart';
import '../repository/seller_listings_repository.dart';

/// Which bucket the products screen is showing.
final sellerBucketProvider = StateProvider<SellerListingBucket>(
  (ref) => SellerListingBucket.active,
);

/// The product list's search box.
final sellerListingQueryProvider = StateProvider<String>((ref) => '');

/// How the table is ordered. Web opens on price, highest first.
final sellerSortProvider = StateProvider<ListingSort>(
  (ref) => const ListingSort(ListingSortCol.price),
);

/// The seller's listings for the selected bucket and search.
final sellerListingsProvider = FutureProvider<List<SellerListing>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return const <SellerListing>[];

  final bucket = ref.watch(sellerBucketProvider);
  // Draft and Preferensi read elsewhere; asking `listings` for them would
  // spend a round trip to be handed rows that can never match the bucket.
  if (!bucket.isListingBucket) return const <SellerListing>[];

  final query = ref.watch(sellerListingQueryProvider);
  final listings = await ref
      .read(sellerListingsRepositoryProvider)
      .fetchListings(bucket: bucket, query: query);
  return ref.watch(sellerSortProvider).apply(listings);
});

/// The seller's unposted drafts, for the Draft tab.
final sellerDraftsProvider = FutureProvider<List<SellerDraft>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const <SellerDraft>[]);
  return ref.read(sellerListingsRepositoryProvider).fetchDrafts();
});

/// The seller's listing defaults, for the Preferensi tab.
final listingDefaultsProvider = FutureProvider<ListingDefaults>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const ListingDefaults());
  return ref.read(sellerListingsRepositoryProvider).fetchListingDefaults();
});

/// Runs a listing mutation and refreshes the list.
///
/// Returns an error message, or null on success. Kept in one place so every
/// action on the products screen invalidates the same things — the list
/// itself, and the dashboard counters that read from the same rows.
class SellerListingActions {
  SellerListingActions(this._ref);

  final Ref _ref;

  Future<String?> archive(String slug) => _run(() => _repo.archive(slug));

  Future<String?> unarchive(String slug) => _run(() => _repo.unarchive(slug));

  Future<String?> restock(String slug, int quantity) =>
      _run(() => _repo.restock(slug, quantity));

  Future<String?> setAcceptsOffers(String slug, bool enabled) =>
      _run(() => _repo.setAcceptsOffers(slug, enabled));

  Future<String?> setAutoRelist(String slug, bool enabled) =>
      _run(() => _repo.setAutoRelist(slug, enabled));

  SellerListingsRepository get _repo =>
      _ref.read(sellerListingsRepositoryProvider);

  Future<String?> _run(Future<String?> Function() action) async {
    final error = await action();
    if (error == null) _ref.invalidate(sellerListingsProvider);
    return error;
  }
}

final sellerListingActionsProvider = Provider(SellerListingActions.new);
