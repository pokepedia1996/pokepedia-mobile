import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/models/dispute_model.dart';
import '../repository/models/order_model.dart';
import '../repository/orders_repository.dart';

final ordersRepositoryProvider = Provider((ref) => OrdersRepository());

final ordersProvider = FutureProvider<List<OrderModel>>((ref) {
  return ref.read(ordersRepositoryProvider).fetchOrders();
});

final orderDetailProvider = FutureProvider.family<OrderModel?, String>((
  ref,
  slug,
) {
  return ref.read(ordersRepositoryProvider).fetchOrder(slug);
});

final orderDisputeProvider = FutureProvider.family<DisputeModel?, String>((
  ref,
  orderSlug,
) {
  return ref.read(ordersRepositoryProvider).fetchDispute(orderSlug);
});
