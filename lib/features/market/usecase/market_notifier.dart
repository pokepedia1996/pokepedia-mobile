import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/store_model.dart';
import '../../expansions/usecase/expansions_notifier.dart';
import '../repository/market_repository.dart';
import '../repository/models/listing_facets.dart';
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

final marketListingsProvider = FutureProvider<List<ListingModel>>((ref) {
  final bucket = ref.watch(bucketProvider);
  final query = ref.watch(marketQueryProvider);
  final sort = ref.watch(marketSortProvider);
  final filters = ref.watch(marketFiltersProvider);
  return ref
      .read(marketRepositoryProvider)
      .fetchListings(
        bucket: bucket,
        query: query,
        sort: sort,
        filters: filters,
      );
});

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
/// `user_id`, which is what `trade_ratings` and the counts RPC take.
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
