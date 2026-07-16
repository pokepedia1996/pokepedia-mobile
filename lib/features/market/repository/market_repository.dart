import '../../../shared/data/dummy_catalog.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/store_model.dart';

enum MarketBucket { all, listing, buylist, toko }

/// Data access for the Market feature. Stands in for
/// `loadMarketplaceListingsPage` / `loadStoreDirectoryPage` on the web
/// while this pass only ports the UI with dummy data.
class MarketRepository {
  Future<List<ListingModel>> fetchListings({
    required MarketBucket bucket,
    String query = '',
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final q = query.trim().toLowerCase();
    return DummyCatalog.listings.where((l) {
      final matchesBucket = switch (bucket) {
        MarketBucket.all => true,
        MarketBucket.listing => l.side == ListingSide.ask,
        MarketBucket.buylist => l.side == ListingSide.bid,
        MarketBucket.toko => true,
      };
      final matchesQuery = q.isEmpty || l.card.name.toLowerCase().contains(q);
      return matchesBucket && matchesQuery;
    }).toList();
  }

  Future<List<StoreModel>> fetchStores({String query = ''}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final q = query.trim().toLowerCase();
    return DummyCatalog.stores
        .where((s) => q.isEmpty || s.storeName.toLowerCase().contains(q))
        .toList();
  }

  Future<StoreModel?> fetchStore(String handle) async {
    await Future.delayed(const Duration(milliseconds: 150));
    for (final s in DummyCatalog.stores) {
      if (s.handle == handle) return s;
    }
    return null;
  }

  Future<List<ListingModel>> fetchStoreListings(String handle) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return DummyCatalog.listings.where((l) => l.storeSlug == handle).toList();
  }
}
