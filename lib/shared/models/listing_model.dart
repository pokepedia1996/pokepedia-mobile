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

  static ListingStatus fromRaw(String? raw) {
    switch (raw) {
      case 'matched':
        return ListingStatus.matched;
      case 'expired':
        return ListingStatus.expired;
      case 'cancelled':
        return ListingStatus.cancelled;
      case 'open':
      default:
        return ListingStatus.open;
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

  /// Maps a `listings` row joined with its `cards` row and the seller's
  /// store info (fetched separately since `listings.user_id` and
  /// `seller_profiles.user_id` both reference `auth.users` rather than one
  /// another directly, so PostgREST can't embed them in one query).
  factory ListingModel.fromRow(
    Map<String, dynamic> row, {
    required CardModel card,
    required String storeSlug,
    required String storeName,
    required bool isVerified,
    required String cityName,
  }) {
    return ListingModel(
      id: row['id'] as int,
      slug: row['slug'] as String? ?? '',
      side: (row['side'] as String?) == 'bid' ? ListingSide.bid : ListingSide.ask,
      price: row['price'] as int? ?? 0,
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      quantity: row['quantity'] as int? ?? 0,
      qtyLocked: row['qty_locked'] as int? ?? 0,
      card: card,
      storeSlug: storeSlug,
      storeName: storeName,
      isVerified: isVerified,
      cityName: cityName,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      status: ListingStatusX.fromRaw(row['status'] as String?),
      acceptsOffers: row['accepts_offers'] as bool? ?? false,
      viewCount: (row['view_count'] as num?)?.toInt() ?? 0,
    );
  }
}
