import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/device_fingerprint.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../notifications/usecase/notifications_notifier.dart';
import '../repository/cart_repository.dart';
import '../repository/models/cart_item.dart';
import 'cart_deals.dart';

final cartRepositoryProvider = Provider(
  (ref) => CartRepository(
    ref.read(supabaseClientProvider),
    ref.read(pokepediaApiProvider),
    ref.read(deviceFingerprintProvider),
  ),
);

/// Rough estimate shown before checkout — real shipping is priced per
/// seller/courier during the real checkout flow, handed off to
/// pokepedia.id (`AppConfig.appUrl`) rather than computed on-device.
const flatShippingCost = 15000;

/// Cart state backed by Supabase directly (see [CartRepository]). `build()`
/// seeds an empty list and kicks off an async load so `cartProvider`
/// consumers don't need `AsyncValue` handling — the cart simply goes from
/// empty to populated once the fetch resolves.
///
/// The load is keyed to the signed-in user rather than fired once at
/// startup. `CartRepository.fetchCart` returns nothing when there is no
/// session, and `supabase_flutter` restores a persisted session
/// asynchronously — so a single fetch at launch usually ran while
/// `currentUser` was still null, came back empty, and was never retried.
/// The rows were in `cart_items` the whole time; nothing read them again
/// until something else happened to call [refresh], which made a
/// database-backed cart behave as if it only lasted for the session.
///
/// Watching the id also empties the cart on sign-out and loads the right
/// one on sign-in, instead of leaving the previous account's items on
/// screen.
class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    // `select` so a token refresh, which re-emits the same user, doesn't
    // trigger a refetch — only an actual change of account does.
    final userId = ref.watch(authProvider.select((a) => a.valueOrNull?.id));
    if (userId == null) return const [];

    // The server adds to this cart on its own — `accept_offer` inserts the
    // accepted listing, `accept_bid_proposal` opens a deal — so like web's
    // cart-count-context the cart follows the table, the notification list
    // and the app coming back, not only the buyer's own adds.
    final repo = ref.read(cartRepositoryProvider);
    final channel = repo.subscribeToCart(refresh);
    ref.onDispose(() {
      if (channel != null) repo.unsubscribe(channel);
    });
    ref.listen(notificationsProvider, (previous, next) {
      if (previous?.hasValue != true || !next.hasValue) return;
      if (identical(previous!.value, next.value)) return;
      reloadAll();
    });
    final lifecycle = AppLifecycleListener(onResume: reloadAll);
    ref.onDispose(lifecycle.dispose);

    Future.microtask(refresh);
    return const [];
  }

  /// How many optimistic adds are in flight, and what they add up to.
  ///
  /// Ports the web's `cart-count-context` pending-delta: the badge moves on
  /// the first frame rather than after a round trip, and settles behind the
  /// user. Kept as a count rather than fabricated `CartItem`s — the cart
  /// list is server truth, and inventing rows in it would put a card on the
  /// cart screen that the server hasn't agreed to.
  int _pendingDelta = 0;
  int _openPending = 0;

  int get pendingDelta => _pendingDelta;

  /// The lines and the accepted deals together — what opening the cart,
  /// returning to the app or a new notification should re-read.
  Future<void> reloadAll() async {
    ref.invalidate(cartDealsProvider);
    await refresh();
  }

  Future<void> refresh() async {
    final items = await ref.read(cartRepositoryProvider).fetchCart();
    // An open optimistic write owns the count right now; a response that
    // started before it would clobber the delta on its way in.
    if (_openPending > 0) return;
    state = items;
  }

  /// Adds [quantity] of the listing [listingId] to the cart. Throws
  /// [CartException] on a business-rule rejection (stock, self-trade,
  /// phone-verify, ban, etc — see `CartException.message`).
  Future<void> add(int listingId, int quantity) async {
    if (ref.read(authProvider).valueOrNull == null) {
      throw const CartException(
        'unauthorized',
        serverMessage: 'Masuk dulu untuk menambah ke keranjang.',
      );
    }

    // `add_to_cart` upserts the quantity rather than accumulating, so adding
    // a listing that's already in the cart changes no count. Only a genuinely
    // new line moves the badge.
    final alreadyCarted = state.any((i) => i.listing.id == listingId);
    final delta = alreadyCarted ? 0 : 1;
    if (delta != 0) {
      _pendingDelta += delta;
      _openPending++;
      ref.notifyListeners();
    }

    try {
      await ref.read(cartRepositoryProvider).add(listingId, quantity);
    } catch (_) {
      // Roll the badge back before the error reaches the caller, so the
      // count never keeps a card the server refused.
      if (delta != 0) {
        _pendingDelta -= delta;
        _openPending--;
        ref.notifyListeners();
      }
      rethrow;
    }

    // Settle: drop the optimistic delta and take the server's list.
    if (delta != 0) {
      _openPending--;
      _pendingDelta -= delta;
    }
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

  /// Removes the lines a checkout just took, leaving anything the buyer
  /// left unticked.
  ///
  /// The server locks the stock but does not empty the cart —
  /// `lock_cart_for_payment` only raises `qty_locked` — so without this the
  /// buyer returns from paying to a cart still holding what they bought.
  Future<void> removeItems(Iterable<int> cartItemIds) async {
    final repo = ref.read(cartRepositoryProvider);
    for (final id in cartItemIds) {
      try {
        await repo.remove(id);
      } on Object {
        // Best effort: a line that refuses to go is a stale cart row, not a
        // reason to hold up a buyer who has already paid.
      }
    }
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

/// What the cart badge shows: the real lines, the accepted bid deals
/// waiting to be paid, and anything mid-flight.
///
/// Separate from `cartProvider` because the two answer different questions —
/// the list is what the server has agreed to, the count is what the buyer
/// just did. Deals count as web's `fetchCartCount` counts them: `kind = 'bid'`
/// only.
final cartCountProvider = Provider<int>((ref) {
  final items = ref.watch(cartProvider);
  final deals = ref.watch(cartDealsProvider).valueOrNull ?? const [];
  final bidDeals = deals.where((deal) => deal.kind == 'bid').length;
  return items.length +
      bidDeals +
      ref.watch(cartProvider.notifier).pendingDelta;
});
