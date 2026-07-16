import '../../../shared/data/dummy_catalog.dart';
import '../../../shared/models/listing_model.dart';
import 'models/cart_item.dart';

/// Seeds an illustrative starting cart. Stands in for the web's
/// Supabase-backed cart (`/api/cart`) while this pass only ports the UI
/// with dummy data.
class CartRepository {
  List<CartItem> seedCart() {
    final asks = DummyCatalog.listings
        .where((l) => l.side == ListingSide.ask)
        .take(2)
        .toList();
    return [for (final l in asks) CartItem(listing: l, quantity: 1)];
  }
}
