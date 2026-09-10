import '../../../../shared/models/card_condition.dart';

/// What the `place_order` RPC answered. Every failure comes back as a
/// machine-readable `error` string in the jsonb payload rather than a
/// thrown exception, so the sheet can react per case (re-price a duplicate,
/// send the user off to verify a phone, ...).
enum PlaceOrderStatus { ok, duplicate, failed }

class PlaceOrderResult {
  const PlaceOrderResult._(this.status, {this.code, this.existingPrice});

  const PlaceOrderResult.ok() : this._(PlaceOrderStatus.ok);

  const PlaceOrderResult.duplicate(int existingPrice)
    : this._(PlaceOrderStatus.duplicate, existingPrice: existingPrice);

  const PlaceOrderResult.failed(String code)
    : this._(PlaceOrderStatus.failed, code: code);

  final PlaceOrderStatus status;

  /// The RPC's `error` string, e.g. `phone_not_verified`.
  final String? code;

  /// Price of the open listing that collided, for the "replace it?" prompt.
  final int? existingPrice;

  bool get isOk => status == PlaceOrderStatus.ok;

  /// Indonesian copy for each `place_order` error branch. Unknown codes
  /// fall back to a generic message rather than leaking the raw string.
  String get messageId {
    switch (code) {
      case 'unauthorized':
        return 'Masuk dulu untuk memasang order.';
      case 'phone_not_verified':
        return 'Nomor HP kamu belum diverifikasi.';
      case 'invalid_side':
        return 'Jenis order tidak valid.';
      case 'trading_disabled':
        return 'Kartu ini belum bisa diperdagangkan.';
      case 'bidding_banned':
        return 'Akun kamu sedang dibatasi untuk memasang bid.';
      case 'invalid_condition':
        return 'Kondisi kartu tidak valid.';
      case 'invalid_price':
        return 'Harga tidak valid.';
      case 'invalid_quantity':
        return 'Jumlah harus antara 1 dan 99.';
      case 'seller_profile_incomplete':
        return 'Lengkapi profil penjual dulu sebelum memasang ask.';
      case 'no_couriers':
        return 'Pilih minimal satu kurir di pengaturan penjual.';
      case 'photo_required':
        return 'Ask di atas Rp100.000 wajib menyertakan foto kartu.';
      case 'cross_side_self_trade':
        return 'Kamu sudah punya order di sisi berlawanan untuk kartu dan '
            'kondisi ini.';
      default:
        return 'Gagal memasang order. Coba lagi.';
    }
  }
}

/// The gates `place_order` checks before it will accept an order, read up
/// front so the sheet can explain the blocker instead of letting the RPC
/// reject a filled-in form.
class TradeEligibility {
  const TradeEligibility({
    this.phoneVerified = false,
    this.biddingBanned = false,
    this.sellerActive = false,
    this.hasCouriers = false,
  });

  final bool phoneVerified;
  final bool biddingBanned;
  final bool sellerActive;
  final bool hasCouriers;

  bool get canBid => phoneVerified && !biddingBanned;
  bool get canAsk => phoneVerified && sellerActive && hasCouriers;
}

/// An open ask a bid would be able to buy outright, ported from
/// `/api/listings/matching-asks` — shown before the bid is placed so the
/// buyer can just buy instead of waiting.
class MatchingAsk {
  const MatchingAsk({
    required this.slug,
    required this.cardId,
    required this.price,
    required this.condition,
    required this.available,
    required this.storeSlug,
    required this.storeName,
  });

  final String slug;
  final int cardId;
  final int price;
  final CardCondition condition;
  final int available;
  final String storeSlug;
  final String storeName;
}
