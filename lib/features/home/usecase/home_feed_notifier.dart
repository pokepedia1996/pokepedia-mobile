import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/listing_model.dart';
import '../../market/usecase/market_notifier.dart';

/// How many listings the Beranda feed shows before "Lihat semua".
const _feedLimit = 6;

/// The feed's own sort. Deliberately separate from `marketSortProvider`:
/// Beranda and the Market tab are different surfaces, and sorting one should
/// not silently reorder the other.
final homeFeedSortProvider = StateProvider<MarketSort>(
  (ref) => MarketSort.createdDesc,
);

/// Recent marketplace listings for the Beranda feed.
final homeFeedProvider = FutureProvider<List<ListingModel>>((ref) async {
  final sort = ref.watch(homeFeedSortProvider);
  final listings = await ref
      .read(marketRepositoryProvider)
      .fetchListings(bucket: MarketBucket.listing, sort: sort);
  return listings.take(_feedLimit).toList();
});
