import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/repository/models/order_rating.dart';
import '../../orders/repository/models/seller_order_detail.dart';
import '../../orders/usecase/orders_notifier.dart';

/// One order as its seller, keyed by `orders.slug`.
///
/// Null means the row isn't this user's to sell — the repository filters on
/// `seller_id` because `orders_select_own` would otherwise hand a buyer
/// their own order wearing the seller's screen.
final sellerOrderDetailProvider =
    FutureProvider.family<SellerOrderDetail?, String>(
      (ref, slug) => ref.read(ordersRepositoryProvider).fetchSellerOrder(slug),
    );

/// The rating this seller already left on the buyer of an order, if any —
/// the seller-side twin of `orderRatingProvider`.
final sellerOrderRatingProvider = FutureProvider.family<OrderRating?, String>((
  ref,
  slug,
) async {
  final detail = await ref.watch(sellerOrderDetailProvider(slug).future);
  if (detail == null) return null;
  return ref.read(ordersRepositoryProvider).fetchMyRating(detail.order);
});
