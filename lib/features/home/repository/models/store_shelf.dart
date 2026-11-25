import '../../../../shared/models/listing_model.dart';
import '../../../../shared/models/store_model.dart';

/// One toko on Beranda's "Listing baru dari toko": the store, and its newest
/// listings as a shelf of tiles.
class StoreShelf {
  const StoreShelf({required this.store, required this.listings});

  final StoreModel store;
  final List<ListingModel> listings;
}

/// A page of shelves, and where the next one starts.
class StoreShelfPage {
  const StoreShelfPage({
    required this.shelves,
    required this.nextOffset,
    required this.hasMore,
  });

  final List<StoreShelf> shelves;

  /// The store directory's offset after this page. Counts every store the
  /// page read, including any left out for having nothing on sale.
  final int nextOffset;
  final bool hasMore;
}
