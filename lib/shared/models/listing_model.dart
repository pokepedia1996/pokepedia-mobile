import '../../core/utils/image_url.dart';
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
    this.expansionSetSymbolUrl,
    this.variantKey,
    this.sellerAvatarUrl,
    this.storeLogoUrl,
    this.sellerFeedbackScore = 0,
    this.photoUrls = const [],
    this.sellerId = '',
  });

  final int id;

  /// `listings.user_id` — the seller. Checkout groups and quotes shipping
  /// per seller, and the courier choices it posts are keyed by this, so it
  /// can't be inferred from the store slug.
  final String sellerId;

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

  /// `expansions.set_symbol_url` — shown next to the ASK/BID row, falling
  /// back to the plain expansion code text when absent (mirrors web's
  /// `setSymbol` in `storefront-listing-card.tsx`).
  final String? expansionSetSymbolUrl;

  /// `listings.variant_key`, falling back to [CardModel.variant] — mirrors
  /// web's `listing.variant_key ?? listing.card_variant`.
  final String? variantKey;
  final String? sellerAvatarUrl;
  final String? storeLogoUrl;

  /// `seller_profiles`' reputation score (`positive - negative` review
  /// counts), used by the seller footer's reputation star.
  final int sellerFeedbackScore;

  /// `listings.photo_urls` — the seller's own photos of this exact copy. The
  /// per-seller card page shows the first as the hero image (falling back to
  /// the catalog artwork) with the rest as thumbnails, like `heroPhotos` in
  /// `store-card-detail.tsx`.
  final List<String> photoUrls;

  /// `quantity - qty_locked`, i.e. what a buyer can actually purchase.
  int get available => quantity - qtyLocked;

  /// The seller's avatar/logo image, preferring the store logo — mirrors
  /// `resolveSellerDisplay`'s `storeLogoUrl ?? avatarUrl`.
  String? get sellerImageUrl => storeLogoUrl ?? sellerAvatarUrl;

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
    String? sellerAvatarUrl,
    String? storeLogoUrl,
    int sellerFeedbackScore = 0,
  }) {
    return ListingModel(
      id: row['id'] as int,
      sellerId: row['user_id'] as String? ?? '',
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
      sellerAvatarUrl: proxyImageUrl(sellerAvatarUrl),
      storeLogoUrl: proxyImageUrl(storeLogoUrl),
      sellerFeedbackScore: sellerFeedbackScore,
      photoUrls: ((row['photo_urls'] as List?) ?? const [])
          .map((u) => proxyImageUrl(u as String?))
          .whereType<String>()
          .toList(),
    );
  }

  /// Ports the `get_recent_marketplace_listings` RPC row
  /// (`features/market/api/storefront-data.server.ts`) — a flattened row
  /// with the card and seller info already joined server-side, unlike
  /// [fromRow]'s two-step fetch. This shape doesn't carry `category` or
  /// `details`, so the resulting [CardModel] is display-only (fine for
  /// [ListingCard], which only reads `name`/`imageUrl`/`collectorNumber`)
  /// — anything opening a full card page from a listing should refetch by
  /// `card_id` instead of relying on this card object.
  factory ListingModel.fromMarketplaceRow(Map<String, dynamic> row) {
    final expansionCode = row['expansion_code'] as String? ?? '';
    final card = CardModel(
      id: row['card_id'] as int,
      category: CardCategory.pokemon,
      nameId: row['card_name'] as String? ?? '',
      expansionCode: expansionCode,
      packSlug: expansionCode.toLowerCase(),
      collectorNumber: row['card_number'] as String? ?? '',
      rarity: row['card_rarity'] as String?,
      language: CardLanguageX.fromRaw(row['card_language'] as String?),
      variant: row['card_variant'] as String? ?? 'normal',
      imageUrl: proxyImageUrl(row['card_image'] as String?),
    );
    return ListingModel(
      id: (row['id'] as num).toInt(),
      slug: row['slug'] as String? ?? '',
      side: (row['side'] as String?) == 'bid' ? ListingSide.bid : ListingSide.ask,
      price: row['price'] as int? ?? 0,
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      quantity: row['quantity'] as int? ?? 0,
      qtyLocked: row['qty_locked'] as int? ?? 0,
      card: card,
      storeSlug: row['store_slug'] as String? ?? '',
      storeName: row['store_name'] as String? ?? 'Toko',
      isVerified: row['is_verified'] as bool? ?? false,
      cityName: row['city_name'] as String? ?? '',
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      acceptsOffers: false,
      viewCount: (row['view_count'] as num?)?.toInt() ?? 0,
      expansionSetSymbolUrl: proxyImageUrl(row['expansion_set_symbol_url'] as String?),
      variantKey: row['variant_key'] as String?,
      sellerAvatarUrl: proxyImageUrl(row['avatar_url'] as String?),
      storeLogoUrl: proxyImageUrl(row['store_logo_url'] as String?),
      sellerFeedbackScore: (row['seller_feedback_score'] as num?)?.toInt() ?? 0,
    );
  }
}
