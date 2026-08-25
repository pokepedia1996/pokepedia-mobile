import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/models/cart_item.dart';
import 'cart_notifier.dart';

/// Which cart lines the buyer is actually checking out.
///
/// Ports the web cart's per-item selection, which isn't cosmetic: the
/// checkout page reads it (`?s=slug,slug`) and `POST /api/cart/checkout`
/// takes `selectedCartItemIds`. Without it, a buyer with ten cards in the
/// cart can only ever buy all ten.
///
/// Modelled as *exclusions* rather than inclusions. Everything available is
/// selected by default, as on the web, and the cart reloads on every add,
/// removal and quantity change — so tracking what was ticked would keep
/// re-ticking lines the buyer had just cleared. Tracking what they cleared
/// survives those reloads, and a line that leaves the cart takes its
/// exclusion with it.
class CartSelectionNotifier extends Notifier<Set<int>> {
  /// `cart_items.id` values the buyer explicitly unticked.
  final Set<int> _excluded = {};

  @override
  Set<int> build() {
    final items = ref.watch(cartProvider);
    // Drop exclusions for lines that are no longer in the cart, so an id
    // reused later doesn't arrive pre-unticked.
    _excluded.removeWhere(
      (id) => !items.any((item) => item.cartItemId == id),
    );

    return {
      for (final item in items)
        if (item.isAvailable && !_excluded.contains(item.cartItemId))
          item.cartItemId,
    };
  }

  void toggle(int cartItemId) {
    if (_excluded.remove(cartItemId)) {
      state = {...state, cartItemId};
      return;
    }
    _excluded.add(cartItemId);
    state = {...state}..remove(cartItemId);
  }

  /// Ports the per-seller checkbox: everything available under that seller,
  /// on or off together.
  void toggleSeller(String sellerId, {required bool selected}) {
    final ids = ref
        .read(cartProvider)
        .where((i) => i.listing.sellerId == sellerId && i.isAvailable)
        .map((i) => i.cartItemId)
        .toSet();
    _apply(ids, selected: selected);
  }

  /// Ports "Pilih Semua".
  void toggleAll({required bool selected}) {
    final ids = ref
        .read(cartProvider)
        .where((i) => i.isAvailable)
        .map((i) => i.cartItemId)
        .toSet();
    _apply(ids, selected: selected);
  }

  void _apply(Set<int> ids, {required bool selected}) {
    if (selected) {
      _excluded.removeAll(ids);
      state = {...state, ...ids};
    } else {
      _excluded.addAll(ids);
      state = {...state}..removeAll(ids);
    }
  }
}

final cartSelectionProvider =
    NotifierProvider<CartSelectionNotifier, Set<int>>(
      CartSelectionNotifier.new,
    );

/// The selected lines themselves, in cart order.
final selectedCartItemsProvider = Provider<List<CartItem>>((ref) {
  final selected = ref.watch(cartSelectionProvider);
  return ref
      .watch(cartProvider)
      .where((item) => selected.contains(item.cartItemId))
      .toList();
});

/// What the buyer will pay for what they picked.
final selectedSubtotalProvider = Provider<int>((ref) {
  return ref
      .watch(selectedCartItemsProvider)
      .fold(0, (sum, item) => sum + item.subtotal);
});
