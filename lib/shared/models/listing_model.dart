import 'card_condition.dart';
import 'card_model.dart';

/// `listings.side` check constraint.
enum ListingSide { ask, bid }

/// `listings.status` check constraint.
enum ListingStatus { open, matched, expired, cancelled }

extension ListingStatusX on ListingStatus {
  String get labelId {
    switch (this) {
      case ListingStatus.open:
        return 'Aktif';
      case ListingStatus.matched:
        return 'Terjual';
      case ListingStatus.expired:
        return 'Kedaluwarsa';
      case ListingStatus.cancelled:
        return 'Dibatalkan';
    }
  }
}

/// A marketplace listing (ask = for sale / WTS, bid = wanted / WTB),
/// mirroring `public.listings` in
/// `supabase/migrations/00000000000000_baseline.sql`.
class ListingModel {
  const ListingModel({
    required this.id,
    required this.slug,
    required this.side,
    required this.price,
    required this.condition,
    required this.quantity,
    required this.card,
    required this.storeSlug,
    required this.storeName,
    required this.isVerified,
    required this.cityName,
    required this.createdAt,
    this.qtyLocked = 0,
    this.status = ListingStatus.open,
    this.acceptsOffers = false,
    this.isFeatured = false,
    this.viewCount = 0,
  });

  final int id;
  final String slug;
  final ListingSide side;
  final int price;
  final CardCondition condition;
  final int quantity;
  final int qtyLocked;
  final CardModel card;
  final String storeSlug;
  final String storeName;
  final bool isVerified;
  final String cityName;
  final DateTime createdAt;
  final ListingStatus status;
  final bool acceptsOffers;
  final bool isFeatured;
  final int viewCount;

  /// `quantity - qty_locked`, i.e. what a buyer can actually purchase.
  int get available => quantity - qtyLocked;
}
