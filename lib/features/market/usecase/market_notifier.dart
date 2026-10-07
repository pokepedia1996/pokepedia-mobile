import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/store_model.dart';
import '../../expansions/usecase/expansions_notifier.dart';
import '../repository/market_repository.dart';
import '../repository/models/listing_facets.dart';
import '../repository/models/market_page.dart';
import '../repository/models/store_feedback.dart';
import 'market_filters.dart';

export '../repository/market_repository.dart' show MarketBucket;
export '../repository/models/listing_facets.dart';
export 'market_filters.dart';

final marketRepositoryProvider = Provider(
  (ref) => MarketRepository(ref.read(supabaseClientProvider)),
);

final bucketProvider = StateProvider<MarketBucket>((ref) => MarketBucket.all);
final marketQueryProvider = StateProvider<String>((ref) => '');
final marketSortProvider = StateProvider<MarketSort>(
  (ref) => MarketSort.createdDesc,
);
final marketFiltersProvider = StateProvider<MarketFilters>(
  (ref) => const MarketFilters(),
);

/// The option lists behind the filter sheet. Keyed by tab only — the counts
/// describe what the tab holds, not what the current filters leave, so they
/// survive every tick inside the sheet instead of refetching on each one.
final marketFacetsProvider = FutureProvider<ListingFacets>((ref) {
  final bucket = ref.watch(bucketProvider);
  return ref.read(marketRepositoryProvider).fetchListingFacets(bucket);
});

/// The marketplace feed and how far through it we are.
class MarketListingsState {
  const MarketListingsState({
    this.listings = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasNext = false,
    this.error = false,
    this.cursor,
  });

  final List<ListingModel> listings;

  /// The first page is in flight — the grid shows a loader in place of
  /// everything. [loadingMore] is the later pages, which append under rows
  /// the user is already reading.
  final bool loading;
  final bool loadingMore;
  final bool hasNext;
  final bool error;
  final MarketCursor? cursor;

  MarketListingsState copyWith({
    List<ListingModel>? listings,
    bool? loading,
    bool? loadingMore,
    bool? hasNext,
    bool? error,
    MarketCursor? cursor,
  }) {
    return MarketListingsState(
      listings: listings ?? this.listings,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasNext: hasNext ?? this.hasNext,
      error: error ?? this.error,
      cursor: cursor ?? this.cursor,
    );
  }
}

/// The marketplace feed, paged.
///
/// It used to be a `FutureProvider` fetching a single hardcoded page of 40
/// with `p_offset: 0`, and nothing could reach row 41. Rebuilt on every
/// bucket/sort/filter/query change, because each of those is a different
/// feed and the cursor from the old one means nothing in the new.
class MarketListingsNotifier extends Notifier<MarketListingsState> {
  @override
  MarketListingsState build() {
    // Watched, so changing any of them tears this notifier down and rebuilds
    // it — which is exactly the reset the old provider got for free.
    final bucket = ref.watch(bucketProvider);
    final query = ref.watch(marketQueryProvider);
    final sort = ref.watch(marketSortProvider);
    final filters = ref.watch(marketFiltersProvider);

    Future.microtask(
      () => _load(bucket: bucket, query: query, sort: sort, filters: filters),
    );
    return const MarketListingsState();
  }

  Future<void> _load({
    required MarketBucket bucket,
    required String query,
    required MarketSort sort,
    required MarketFilters filters,
  }) async {
    try {
      final page = await ref
          .read(marketRepositoryProvider)
          .fetchListings(
            bucket: bucket,
            query: query,
            sort: sort,
            filters: filters,
          );
      state = MarketListingsState(
        listings: page.listings,
        loading: false,
        hasNext: page.hasNext,
        cursor: page.cursor,
      );
    } catch (_) {
      state = const MarketListingsState(loading: false, error: true);
    }
  }

  /// Appends the next page. Safe to call on every scroll frame — it returns
  /// immediately unless there is another page and nothing already in flight.
  Future<void> loadMore() async {
    final cursor = state.cursor;
    if (state.loading || state.loadingMore || !state.hasNext) return;
    if (cursor == null) return;

    state = state.copyWith(loadingMore: true);
    try {
      final page = await ref
          .read(marketRepositoryProvider)
          .fetchListings(
            bucket: ref.read(bucketProvider),
            query: ref.read(marketQueryProvider),
            sort: ref.read(marketSortProvider),
            filters: ref.read(marketFiltersProvider),
            cursor: cursor,
          );
      state = state.copyWith(
        listings: [...state.listings, ...page.listings],
        loadingMore: false,
        hasNext: page.hasNext,
        // Held from the last *returned* row, so a page emptied by the
        // own-listings filter still advances instead of asking for the same
        // rows forever.
        cursor: page.cursor ?? cursor,
      );
    } catch (_) {
      // The rows already on screen stay; only the next page is lost, and
      // scrolling again retries.
      state = state.copyWith(loadingMore: false);
    }
  }

  /// What the error state's "Coba lagi" calls.
  void retry() => ref.invalidateSelf();
}

final marketListingsProvider =
    NotifierProvider<MarketListingsNotifier, MarketListingsState>(
      MarketListingsNotifier.new,
    );

final marketStoresProvider = FutureProvider<List<StoreModel>>((ref) {
  final query = ref.watch(marketQueryProvider);
  return ref.read(marketRepositoryProvider).fetchStores(query: query);
});

final storeDetailProvider = FutureProvider.family<StoreModel?, String>((
  ref,
  handle,
) {
  return ref.read(marketRepositoryProvider).fetchStore(handle);
});

/// Depends on [storeDetailProvider]'s already-resolved `userId` instead of
/// re-resolving the slug, so viewing a store only pays for the profile RPC
/// once.
final storeListingsProvider = FutureProvider.family<List<ListingModel>, String>(
  (ref, handle) async {
    final store = await ref.watch(storeDetailProvider(handle).future);
    if (store?.userId == null) return const [];
    return ref
        .read(marketRepositoryProvider)
        .fetchStoreListingsByUserId(store!.userId!);
  },
);

/// A seller's feedback summary and their reviews. Keyed by the seller's
/// `user_id`, which is what both feedback RPCs take.
final storeFeedbackSummaryProvider =
    FutureProvider.family<StoreFeedbackSummary, String>((ref, userId) {
      return ref.read(marketRepositoryProvider).fetchFeedbackSummary(userId);
    });

final storeFeedbackProvider =
    FutureProvider.family<List<StoreFeedback>, String>((ref, userId) {
      return ref.read(marketRepositoryProvider).fetchFeedback(userId);
    });

/// Everything the per-seller "product" page needs for one (store, card)
/// pair — composed from three parallel-ish lookups (store profile, card,
/// this seller's listings + reputation) so the page itself only deals with
/// one `AsyncValue`.
typedef StoreCardListingData = ({
  StoreModel store,
  List<ListingModel> listings,
  int otherSellersCount,
  double? positivePct,
  int feedbackScore,
});

/// Everything the WTB detail page needs for one bid: the bid itself, the
/// full card behind it, and the buyer's standing.
typedef BidListingData = ({
  ListingModel listing,
  CardModel card,
  double? positivePct,
  int feedbackScore,
});

/// One WTB bid, by listing slug — backs the page a bid tap opens.
///
/// The card comes from [cardDetailProvider] rather than from the bid row:
/// the listing carries only enough of a card to draw a tile, and this page
/// shows the card's own detail sections underneath.
///
/// Re-reads when the session changes. Both SELECT policies on `listings`
/// require `auth.uid()`, so a guest's fetch comes back empty no matter which
/// bid it is — and the page turns that into a sign-in prompt. Without this
/// watch the empty result would stay cached, and signing in from that prompt
/// would land back on it.
final bidListingProvider = FutureProvider.family<BidListingData?, String>((
  ref,
  slug,
) async {
  ref.watch(authProvider);
  final repo = ref.read(marketRepositoryProvider);
  final listing = await repo.fetchBidListing(slug);
  if (listing == null) return null;

  final card = await ref.watch(cardDetailProvider(listing.card.id).future);
  if (card == null) return null;

  final reputation = listing.sellerId.isEmpty
      ? (positivePct: null, feedbackScore: 0)
      : await repo.fetchReputation(listing.sellerId);

  return (
    listing: listing,
    card: card,
    positivePct: reputation.positivePct,
    feedbackScore: reputation.feedbackScore,
  );
});

/// One seller's open asks for a single card — backs the compact
/// per-seller "product" page a WTS listing tap opens (mirrors
/// `app/market/[slug]/card/[cardId]/page.tsx`).
final storeCardListingsProvider =
    FutureProvider.family<
      StoreCardListingData?,
      ({String storeSlug, int cardId})
    >((ref, key) async {
      final store = await ref.watch(storeDetailProvider(key.storeSlug).future);
      final card = await ref.watch(cardDetailProvider(key.cardId).future);
      if (store == null || card == null) return null;
      final repo = ref.read(marketRepositoryProvider);
      final listingsFuture = repo.fetchCardListingsForSeller(
        cardId: key.cardId,
        card: card,
        store: store,
      );
      final Future<({double? positivePct, int feedbackScore})>
      reputationFuture = store.userId == null
          ? Future.value((positivePct: null, feedbackScore: 0))
          : repo.fetchReputation(store.userId!);
      final listingsResult = await listingsFuture;
      final reputation = await reputationFuture;
      return (
        store: store,
        listings: listingsResult.listings,
        otherSellersCount: listingsResult.otherSellersCount,
        positivePct: reputation.positivePct,
        feedbackScore: reputation.feedbackScore,
      );
    });

/// What a storefront's listing grid is showing: whose, which side, and how
/// it is narrowed and ordered. Every field goes to the server.
typedef StoreFeedKey = ({
  String sellerUserId,
  String side,
  String search,
  String? condition,
  String sort,
});

class StoreFeedState {
  const StoreFeedState({
    this.listings = const [],
    this.hasNext = false,
    this.loading = true,
    this.loadingMore = false,
    this.failed = false,
  });

  final List<ListingModel> listings;
  final bool hasNext;
  final bool loading;
  final bool loadingMore;
  final bool failed;
}

/// A storefront's listings, paged from the server as the grid scrolls.
///
/// Search, condition and sort all re-query rather than narrowing a fetched
/// page: a shop's catalogue runs to thousands, and matching only what had
/// been loaded is how a card the shop plainly stocks came back "Tidak ada
/// kartu yang cocok".
class StoreFeedNotifier
    extends AutoDisposeFamilyNotifier<StoreFeedState, StoreFeedKey> {
  /// A page that answers after its key has been replaced is dropped.
  int _generation = 0;

  @override
  StoreFeedState build(StoreFeedKey key) {
    Future.microtask(_loadFirst);
    return const StoreFeedState();
  }

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    try {
      final page = await _fetch(offset: 0);
      if (generation != _generation) return;
      state = StoreFeedState(
        listings: page,
        hasNext: page.length >= MarketRepository.storeListingsPageSize,
        loading: false,
      );
    } catch (_) {
      if (generation != _generation) return;
      state = const StoreFeedState(loading: false, failed: true);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasNext) return;
    final generation = _generation;
    state = StoreFeedState(
      listings: state.listings,
      hasNext: true,
      loading: false,
      loadingMore: true,
    );
    try {
      final page = await _fetch(offset: state.listings.length);
      if (generation != _generation) return;
      state = StoreFeedState(
        listings: [...state.listings, ...page],
        hasNext: page.length >= MarketRepository.storeListingsPageSize,
        loading: false,
      );
    } catch (_) {
      if (generation != _generation) return;
      // Keeps what is on screen; the next scroll to the end tries again.
      state = StoreFeedState(
        listings: state.listings,
        hasNext: true,
        loading: false,
      );
    }
  }

  Future<void> retry() async {
    state = const StoreFeedState();
    await _loadFirst();
  }

  Future<List<ListingModel>> _fetch({required int offset}) => ref
      .read(marketRepositoryProvider)
      .fetchStoreListingsPage(
        sellerUserId: arg.sellerUserId,
        side: arg.side,
        search: arg.search,
        condition: arg.condition,
        sort: arg.sort,
        offset: offset,
      );
}

final storeFeedProvider =
    AutoDisposeNotifierProviderFamily<
      StoreFeedNotifier,
      StoreFeedState,
      StoreFeedKey
    >(StoreFeedNotifier.new);
