import '../../../../shared/models/listing_model.dart';
import 'cart_item.dart';
import 'checkout_models.dart';

/// The cart split per seller, the way the web checkout stacks its order
/// cards — each seller ships (and is paid out) separately.
class SellerGroup {
  const SellerGroup({
    required this.storeSlug,
    required this.storeName,
    required this.cityName,
    required this.items,
    this.storeLogoUrl,
  });

  final String storeSlug;
  final String storeName;
  final String cityName;
  final List<CartItem> items;
  final String? storeLogoUrl;

  int get subtotal => items.fold(0, (sum, item) => sum + item.subtotal);

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// Groups cart lines by the seller behind each listing, preserving the
  /// order the cart returned them in.
  static List<SellerGroup> from(List<CartItem> items) {
    final byStore = <String, List<CartItem>>{};
    final listingByStore = <String, ListingModel>{};
    for (final item in items) {
      final key = item.listing.storeSlug.isEmpty
          ? item.listing.storeName
          : item.listing.storeSlug;
      byStore.putIfAbsent(key, () => []).add(item);
      listingByStore.putIfAbsent(key, () => item.listing);
    }
    return byStore.entries.map((entry) {
      final listing = listingByStore[entry.key]!;
      return SellerGroup(
        storeSlug: listing.storeSlug,
        storeName: listing.storeName,
        cityName: listing.cityName,
        storeLogoUrl: listing.storeLogoUrl,
        items: entry.value,
      );
    }).toList();
  }
}

/// Either a validated coupon or the reason the code was refused — the
/// `apply_coupon` RPC answers both in the same payload.
///
/// The RPC only *quotes* the discount; redemption happens server-side when
/// the invoice is created, so this is a preview the buyer can trust but
/// hasn't spent yet.
class CouponResult {
  const CouponResult({this.coupon, this.error});

  final AppliedCoupon? coupon;
  final String? error;

  factory CouponResult.fromRpc(Map<String, dynamic>? payload) {
    if (payload == null) {
      return const CouponResult(error: 'Gagal memeriksa kode promo.');
    }
    if (payload['ok'] != true) {
      return CouponResult(
        error: payload['message'] as String? ?? 'Kode promo tidak berlaku.',
      );
    }
    return CouponResult(
      coupon: AppliedCoupon(
        code: payload['code'] as String? ?? '',
        waivesGatewayFee: payload['type'] == 'waive_gateway_fee',
        discountAmount: (payload['discount_amount'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
