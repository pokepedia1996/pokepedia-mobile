import '../../../../shared/models/listing_model.dart';

class CartItem {
  const CartItem({
    required this.cartItemId,
    required this.listing,
    required this.quantity,
    this.offerPrice,
    this.offerRemainingQty,
  });

  /// `cart_items.id` — distinct from [ListingModel.id] (the listing being
  /// bought). Needed by `remove_from_cart`'s `p_cart_item_id` argument.
  final int cartItemId;
  final ListingModel listing;
  final int quantity;

  /// The price of an accepted `listing_offers` row below the list price, and
  /// how many units it still covers — web's `offerDiscountedPrice` /
  /// `offerRemainingQty`. Null when no live offer applies.
  final int? offerPrice;
  final int? offerRemainingQty;

  bool get hasOfferPrice => offerPrice != null;

  /// Ports `offerLineTotal`: the offer price for as many units as the offer
  /// still covers, the list price for the rest.
  int get subtotal {
    final discounted = offerPrice;
    if (discounted == null) return listing.price * quantity;
    final covered = (offerRemainingQty ?? quantity).clamp(0, quantity);
    return discounted * covered + listing.price * (quantity - covered);
  }

  /// Ports `isAvailable` from `lib/cart/shared.ts` — a line can still be in
  /// the cart after the listing closed or sold out underneath the buyer, and
  /// those can't be checked out.
  bool get isAvailable =>
      listing.status == ListingStatus.open && listing.available > 0;

  CartItem copyWith({int? quantity}) => CartItem(
    cartItemId: cartItemId,
    listing: listing,
    quantity: quantity ?? this.quantity,
    offerPrice: offerPrice,
    offerRemainingQty: offerRemainingQty,
  );
}
