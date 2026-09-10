import '../../../../shared/models/listing_model.dart';

class CartItem {
  const CartItem({
    required this.cartItemId,
    required this.listing,
    required this.quantity,
  });

  /// `cart_items.id` — distinct from [ListingModel.id] (the listing being
  /// bought). Needed by `remove_from_cart`'s `p_cart_item_id` argument.
  final int cartItemId;
  final ListingModel listing;
  final int quantity;

  int get subtotal => listing.price * quantity;

  /// Ports `isAvailable` from `lib/cart/shared.ts` — a line can still be in
  /// the cart after the listing closed or sold out underneath the buyer, and
  /// those can't be checked out.
  bool get isAvailable =>
      listing.status == ListingStatus.open && listing.available > 0;

  CartItem copyWith({int? quantity}) => CartItem(
    cartItemId: cartItemId,
    listing: listing,
    quantity: quantity ?? this.quantity,
  );
}
