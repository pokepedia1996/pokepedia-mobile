import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';

import '../repository/models/dispute_model.dart';
import '../repository/models/order_model.dart';
import '../repository/models/order_rating.dart';
import '../repository/models/pending_checkout.dart';
import '../repository/models/seller_order.dart';
import '../repository/orders_repository.dart';

final ordersRepositoryProvider = Provider(
  (ref) => OrdersRepository(ref.read(supabaseClientProvider)),
);

final ordersProvider = FutureProvider<List<OrderModel>>((ref) {
  // Signing out must empty the list rather than leave the last account's
  // orders on screen.
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const <OrderModel>[]);
  return ref.read(ordersRepositoryProvider).fetchOrders();
});

/// The same orders from the other side of the counter — what the signed-in
/// user is selling. Backs the seller dashboard's Pesanan tool.
final sellerOrdersProvider = FutureProvider<List<OrderModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const <OrderModel>[]);
  return ref.read(ordersRepositoryProvider).fetchOrders(asSeller: true);
});

/// The unpaid checkouts sitting against this seller's listings. Separate
/// from [sellerOrdersProvider] because they aren't orders yet — they live in
/// `carts` until the payment lands.
final sellerPendingCheckoutsProvider = FutureProvider<List<PendingCheckout>>((
  ref,
) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const <PendingCheckout>[]);
  return ref.read(ordersRepositoryProvider).fetchPendingCheckouts();
});

/// The buyer's own unpaid checkouts. Separate from [ordersProvider] because
/// they aren't orders yet — the webhook creates those.
final myPendingCheckoutsProvider = FutureProvider<List<PendingCheckout>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const <PendingCheckout>[]);
  return ref.read(ordersRepositoryProvider).fetchMyPendingCheckouts();
});

/// Which tab the seller's Pesanan list is on, and how it's ordered. Held
/// outside the widget so the list survives a detail-page round trip.
final sellerOrderTabProvider = StateProvider<SellerOrderTab>(
  (ref) => SellerOrderTab.all,
);

final sellerOrderSortProvider = StateProvider<SellerOrderSort>(
  (ref) => SellerOrderSort.newest,
);

final sellerOrderQueryProvider = StateProvider<String>((ref) => '');

/// The courier filter, or null for "Semua kurir".
final sellerOrderCourierProvider = StateProvider<String?>((ref) => null);

final orderDetailProvider = FutureProvider.family<OrderModel?, String>((
  ref,
  slug,
) {
  return ref.read(ordersRepositoryProvider).fetchOrder(slug);
});

/// The rating this buyer already left on an order, if any — what decides
/// whether the Penilaian card offers the button or shows the review.
final orderRatingProvider = FutureProvider.family<OrderRating?, String>((
  ref,
  slug,
) async {
  final order = await ref.watch(orderDetailProvider(slug).future);
  if (order == null) return null;
  return ref.read(ordersRepositoryProvider).fetchMyRating(order);
});

final orderDisputeProvider = FutureProvider.family<DisputeModel?, String>((
  ref,
  orderSlug,
) {
  return ref.read(ordersRepositoryProvider).fetchDispute(orderSlug);
});
