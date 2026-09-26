import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../repository/models/seller_listing.dart';
import '../repository/seller_listings_repository.dart';
import 'offers_notifier.dart';

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
/// Web's `?offers=1` — narrows the table to listings holding a live offer.
///
/// A view filter rather than a query parameter: the offer counts are already
/// loaded for the row menus, so this costs nothing the page hasn't paid for.
final sellerOfferFilterProvider = StateProvider<bool>((ref) => false);

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
  final sorted = ref.watch(sellerSortProvider).apply(listings);
  if (!ref.watch(sellerOfferFilterProvider)) return sorted;

  final counts = ref.watch(offerCountsProvider);
  return [
    for (final listing in sorted)
      if (counts.containsKey(listing.slug)) listing,
  ];
});

/// The seller's unposted drafts, for the Draft tab.
/// How many listings sit in each bucket, for the dashboard's tiles.
///
/// Counted by fetching rather than with a SQL `count`: "aktif" is not a
/// column. A listing is active only if it is unarchived *and* still in stock
/// *and* unexpired, and the last two are settled in Dart — see
/// `fetchListings`. A count query would have to reimplement that rule in SQL
/// and then drift from it.
final sellerListingCountsProvider =
    FutureProvider<({int active, int inactive})>((ref) async {
      final user = ref.watch(authProvider).valueOrNull;
      if (user == null) return (active: 0, inactive: 0);

      final repo = ref.read(sellerListingsRepositoryProvider);
      final results = await Future.wait([
        repo.fetchListings(bucket: SellerListingBucket.active),
        repo.fetchListings(bucket: SellerListingBucket.inactive),
      ]);
      return (active: results[0].length, inactive: results[1].length);
    });

/// Which drafts are ticked, by id.
///
/// Selection is what the green card in the design means — not "ready to
/// post". Readiness is already visible from the price field being filled in,
/// and spending the one strong colour on it would leave nothing to say
/// "these are the ones the button at the bottom is about".
final draftSelectionProvider = StateProvider<Set<int>>((ref) => const {});

/// Which drafts the Draft tab is listing.
///
/// A draft is only missing a price — quantity and condition are `NOT NULL`
/// with defaults — so "needs finishing" and "ready to post" is the whole
/// split, and it is worth showing because posting is what the seller is
/// here to do and an unpriced draft cannot be posted.
enum DraftFilter {
  all('Semua'),
  needsWork('Perlu dilengkapi'),
  ready('Siap dipasang');

  const DraftFilter(this.label);

  final String label;

  bool matches(SellerDraft draft) => switch (this) {
    DraftFilter.all => true,
    DraftFilter.needsWork => !draft.isReady,
    DraftFilter.ready => draft.isReady,
  };
}

final draftFilterProvider = StateProvider<DraftFilter>(
  (ref) => DraftFilter.all,
);

/// The draft search box — the card name, matched as typed.
final draftQueryProvider = StateProvider<String>((ref) => '');

/// What the Draft tab actually renders: the drafts left after the chip and
/// the search box have had their say.
final visibleDraftsProvider = Provider<List<SellerDraft>>((ref) {
  final drafts = ref.watch(sellerDraftsProvider).valueOrNull ?? const [];
  final filter = ref.watch(draftFilterProvider);
  final query = ref.watch(draftQueryProvider).trim().toLowerCase();

  return [
    for (final draft in drafts)
      if (filter.matches(draft) &&
          (query.isEmpty || draft.card.name.toLowerCase().contains(query)))
        draft,
  ];
});

/// How many drafts sit in each chip. Counted off the unfiltered list so the
/// numbers don't move as the chips are used — a count that changes when you
/// select it is not a count, it's a result.
final draftCountsProvider = Provider<Map<DraftFilter, int>>((ref) {
  final drafts = ref.watch(sellerDraftsProvider).valueOrNull ?? const [];
  return {
    for (final f in DraftFilter.values) f: drafts.where(f.matches).length,
  };
});

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

  Future<String?> deletePermanent(String slug) =>
      _run(() => _repo.deletePermanent(slug));

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
