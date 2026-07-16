import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/listing_model.dart';
import '../../../shared/models/store_model.dart';
import '../repository/market_repository.dart';

export '../repository/market_repository.dart' show MarketBucket;

final marketRepositoryProvider = Provider((ref) => MarketRepository());

final bucketProvider = StateProvider<MarketBucket>((ref) => MarketBucket.all);
final marketQueryProvider = StateProvider<String>((ref) => '');

final marketListingsProvider = FutureProvider<List<ListingModel>>((ref) {
  final bucket = ref.watch(bucketProvider);
  final query = ref.watch(marketQueryProvider);
  return ref
      .read(marketRepositoryProvider)
      .fetchListings(bucket: bucket, query: query);
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

final storeListingsProvider = FutureProvider.family<List<ListingModel>, String>((
  ref,
  handle,
) {
  return ref.read(marketRepositoryProvider).fetchStoreListings(handle);
});
