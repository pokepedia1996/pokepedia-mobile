import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/cart_repository.dart';
import '../repository/models/cart_item.dart';

final cartRepositoryProvider = Provider((ref) => CartRepository());

const flatShippingCost = 15000;

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => ref.read(cartRepositoryProvider).seedCart();

  void updateQuantity(int listingId, int quantity) {
    if (quantity <= 0) {
      remove(listingId);
      return;
    }
    state = [
      for (final item in state)
        if (item.listing.id == listingId)
          item.copyWith(quantity: quantity)
        else
          item,
    ];
  }

  void remove(int listingId) {
    state = state.where((item) => item.listing.id != listingId).toList();
  }

  void clear() => state = [];

  int get subtotal => state.fold(0, (sum, item) => sum + item.subtotal);
  int get total => state.isEmpty ? 0 : subtotal + flatShippingCost;
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);
