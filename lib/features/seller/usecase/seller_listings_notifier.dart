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

/// Web's `?offers=1` — narrows the table to listings holding a live offer,
/// through `get_seller_listings_page`'s `p_with_offers`.
final sellerOfferFilterProvider = StateProvider<bool>((ref) => false);

/// How many rows each `get_seller_listings_page` call asks for.
const sellerListingsPageSize = 30;

/// The first page of the selected bucket, with the bucket-wide totals.
final sellerListingsPageProvider = FutureProvider<SellerListingsPage>((
  ref,
) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return const SellerListingsPage();

  final bucket = ref.watch(sellerBucketProvider);
  if (!bucket.isListingBucket) return const SellerListingsPage();

  return ref
      .read(sellerListingsRepositoryProvider)
      .fetchListingsPage(
        bucket: bucket,
        query: ref.watch(sellerListingQueryProvider),
        sort: ref.watch(sellerSortProvider),
        withOffers: ref.watch(sellerOfferFilterProvider),
        limit: sellerListingsPageSize,
      );
});

/// The first page's rows — the seam [SellerListingsFeed] seeds from.
final sellerListingsProvider = FutureProvider<List<SellerListing>>((ref) async {
  final page = await ref.watch(sellerListingsPageProvider.future);
  return page.rows;
});

class SellerListingsFeedState {
  const SellerListingsFeedState({
    this.rows = const [],
    this.totalCount = 0,
    this.offersCount,
    this.loading = true,
    this.loadingMore = false,
    this.error = false,
  });

  final List<SellerListing> rows;

  /// Every listing the bucket's filters match, not just those loaded.
  final int totalCount;

  /// Null until the page payload arrives.
  final int? offersCount;
  final bool loading;
  final bool loadingMore;
  final bool error;

  bool get hasMore => rows.length < totalCount;

  SellerListingsFeedState copyWith({
    List<SellerListing>? rows,
    int? totalCount,
    bool? loadingMore,
  }) => SellerListingsFeedState(
    rows: rows ?? this.rows,
    totalCount: totalCount ?? this.totalCount,
    offersCount: offersCount,
    loading: loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error,
  );
}

/// The product list, paged by offset the way web's table pages.
///
/// Rebuilt from the first page whenever the bucket, search, sort or offers
/// filter changes, or a mutation invalidates it; [loadMore] appends after.
class SellerListingsFeed extends Notifier<SellerListingsFeedState> {
  @override
  SellerListingsFeedState build() {
    final first = ref.watch(sellerListingsProvider);
    final page = ref.watch(sellerListingsPageProvider).valueOrNull;
    return first.when(
      loading: () => const SellerListingsFeedState(),
      error: (_, __) =>
          const SellerListingsFeedState(loading: false, error: true),
      data: (rows) => SellerListingsFeedState(
        rows: rows,
        totalCount: page?.totalCount ?? rows.length,
        offersCount: page?.offersCount,
        loading: false,
      ),
    );
  }

  /// Appends the next page. Safe to call on every scroll frame.
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;

    final pending = state.copyWith(loadingMore: true);
    state = pending;
    try {
      final page = await ref
          .read(sellerListingsRepositoryProvider)
          .fetchListingsPage(
            bucket: ref.read(sellerBucketProvider),
            query: ref.read(sellerListingQueryProvider),
            sort: ref.read(sellerSortProvider),
            withOffers: ref.read(sellerOfferFilterProvider),
            offset: pending.rows.length,
            limit: sellerListingsPageSize,
          );
      // A filter change or refresh mid-flight rebuilt the feed; this page
      // belongs to the old one.
      if (!identical(state, pending)) return;
      final seen = {for (final row in pending.rows) row.slug};
      state = pending.copyWith(
        rows: [
          ...pending.rows,
          for (final row in page.rows)
            if (seen.add(row.slug)) row,
        ],
        // An empty page means the total moved under us; stop asking.
        totalCount: page.rows.isEmpty ? pending.rows.length : page.totalCount,
        loadingMore: false,
      );
    } catch (_) {
      if (identical(state, pending)) {
        state = pending.copyWith(loadingMore: false);
      }
    }
  }
}

final sellerListingsFeedProvider =
    NotifierProvider<SellerListingsFeed, SellerListingsFeedState>(
      SellerListingsFeed.new,
    );

/// Per-tab counts from `get_seller_listing_tab_counts`. Empty when signed
/// out or when the call fails, so the tabs simply show no number.
final sellerListingTabCountsProvider =
    FutureProvider<Map<SellerListingBucket, int>>((ref) async {
      final user = ref.watch(authProvider).valueOrNull;
      if (user == null) return const {};
      try {
        return await ref
            .read(sellerListingsRepositoryProvider)
            .fetchTabCounts();
      } catch (_) {
        return const {};
      }
    });

/// How many listings sit in each bucket, for the dashboard's tiles.
final sellerListingCountsProvider =
    FutureProvider<({int active, int inactive})>((ref) async {
      final counts = await ref.watch(sellerListingTabCountsProvider.future);
      return (
        active: counts[SellerListingBucket.active] ?? 0,
        inactive: counts[SellerListingBucket.inactive] ?? 0,
      );
    });

/// Re-reads the product list and every tab count after something changed
/// which listings exist or where they sit.
void refreshSellerListings(Ref ref) => _refresh(ref.invalidate);

/// [refreshSellerListings] for widgets.
void refreshSellerListingsFromWidget(WidgetRef ref) => _refresh(ref.invalidate);

void _refresh(void Function(ProviderOrFamily) invalidate) {
  invalidate(sellerListingsPageProvider);
  invalidate(sellerListingsProvider);
  invalidate(sellerListingTabCountsProvider);
}

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
/// itself, and the tab and dashboard counts that read from the same rows.
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
    if (error == null) refreshSellerListings(_ref);
    return error;
  }
}

final sellerListingActionsProvider = Provider(SellerListingActions.new);
