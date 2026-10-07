import '../../../../shared/models/listing_model.dart';
import 'cart_item.dart';

/// The cart split per seller, the way the web checkout stacks its order
/// cards — each seller ships (and is paid out) separately.
class SellerGroup {
  const SellerGroup({
    required this.storeSlug,
    required this.storeName,
    required this.cityName,
    required this.items,
    this.storeLogoUrl,
  });

  final String storeSlug;
  final String storeName;
  final String cityName;
  final List<CartItem> items;
  final String? storeLogoUrl;

  int get subtotal => items.fold(0, (sum, item) => sum + item.subtotal);

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// Groups cart lines by the seller behind each listing, preserving the
  /// order the cart returned them in.
  static List<SellerGroup> from(List<CartItem> items) {
    final byStore = <String, List<CartItem>>{};
    final listingByStore = <String, ListingModel>{};
    for (final item in items) {
      final key = item.listing.storeSlug.isEmpty
          ? item.listing.storeName
          : item.listing.storeSlug;
      byStore.putIfAbsent(key, () => []).add(item);
      listingByStore.putIfAbsent(key, () => item.listing);
    }
    return byStore.entries.map((entry) {
      final listing = listingByStore[entry.key]!;
      return SellerGroup(
        storeSlug: listing.storeSlug,
        storeName: listing.storeName,
        cityName: listing.cityName,
        storeLogoUrl: listing.storeLogoUrl,
        items: entry.value,
      );
    }).toList();
  }
}
