import '../../../../shared/models/listing_model.dart';

class CartItem {
  const CartItem({required this.listing, required this.quantity});

  final ListingModel listing;
  final int quantity;

  int get subtotal => listing.price * quantity;

  CartItem copyWith({int? quantity}) =>
      CartItem(listing: listing, quantity: quantity ?? this.quantity);
}
