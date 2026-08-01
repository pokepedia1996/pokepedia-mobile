import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_provider.dart';
import '../repository/cart_repository.dart';
import '../repository/models/cart_item.dart';

final cartRepositoryProvider = Provider(
  (ref) => CartRepository(ref.read(supabaseClientProvider)),
);

/// Rough estimate shown before checkout — real shipping is priced per
/// seller/courier during the real checkout flow, handed off to
/// pokepedia.id (`AppConfig.appUrl`) rather than computed on-device.
const flatShippingCost = 15000;

/// Cart state backed by Supabase directly (see [CartRepository]). `build()`
/// seeds an empty list and kicks off an async load so `cartProvider`
/// consumers don't need `AsyncValue` handling — the cart simply goes from
/// empty to populated once the fetch resolves, same shape as the earlier
/// dummy-data pass just with a real network round-trip in between.
class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    Future.microtask(refresh);
    return const [];
  }

  Future<void> refresh() async {
    final items = await ref.read(cartRepositoryProvider).fetchCart();
    state = items;
  }

  /// Adds [quantity] of the listing [listingId] to the cart. Throws
  /// [CartException] on a business-rule rejection (stock, self-trade,
  /// phone-verify, ban, etc — see `CartException.message`).
  Future<void> add(int listingId, int quantity) async {
    await ref.read(cartRepositoryProvider).add(listingId, quantity);
    await refresh();
  }

  Future<void> remove(int cartItemId) async {
    await ref.read(cartRepositoryProvider).remove(cartItemId);
    await refresh();
  }

  /// There's no dedicated "update quantity" RPC — mirrors the web's
  /// remove-then-re-add flow (`cart-client.tsx`'s "Quantity change re-add
  /// flow").
  Future<void> updateQuantity(CartItem item, int quantity) async {
    if (quantity <= 0) {
      await remove(item.cartItemId);
      return;
    }
    final repo = ref.read(cartRepositoryProvider);
    await repo.remove(item.cartItemId);
    await repo.add(item.listing.id, quantity);
    await refresh();
  }

  Future<void> clear() async {
    final repo = ref.read(cartRepositoryProvider);
    for (final item in state) {
      await repo.remove(item.cartItemId);
    }
    await refresh();
  }

  int get subtotal => state.fold(0, (sum, item) => sum + item.subtotal);
  int get total => state.isEmpty ? 0 : subtotal + flatShippingCost;
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);
