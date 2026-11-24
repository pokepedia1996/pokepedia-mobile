import '../../../../core/utils/image_url.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/models/listing_model.dart';
import '../../../../shared/models/store_model.dart';

/// One catalog card a seller tagged on a custom listing — an entry of
/// `get_custom_listing`'s `tags`.
class CustomTaggedCard {
  const CustomTaggedCard({
    required this.cardId,
    required this.name,
    required this.condition,
    required this.quantity,
    required this.expansionCode,
    required this.collectorNumber,
    required this.language,
    this.imageUrl,
  });

  factory CustomTaggedCard.fromJson(Map<String, dynamic> json) =>
      CustomTaggedCard(
        cardId: (json['card_id'] as num?)?.toInt() ?? 0,
        name: json['card_name'] as String? ?? 'Kartu',
        condition: CardConditionX.fromRaw(json['condition'] as String? ?? 'NM'),
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        expansionCode: json['expansion_code'] as String? ?? '',
        collectorNumber: json['collector_number'] as String? ?? '',
        language: CardLanguage.fromRaw(json['language'] as String?),
        imageUrl: proxyImageUrl(json['image_url'] as String?),
      );

  final int cardId;
  final String name;
  final CardCondition condition;
  final int quantity;
  final String expansionCode;
  final String collectorNumber;
  final CardLanguage language;
  final String? imageUrl;

  /// The catalog page this card opens, when it has one to open.
  String? get packSlug => cardId > 0 && expansionCode.isNotEmpty
      ? expansionCode.toLowerCase()
      : null;
}

/// A custom listing as `get_custom_listing` returns it: a seller's own title,
/// description and photos instead of a catalog card, with the cards they
/// tagged on it.
class CustomListingDetail {
  const CustomListingDetail({
    required this.id,
    required this.slug,
    required this.sellerId,
    required this.title,
    required this.price,
    required this.quantity,
    required this.qtyLocked,
    required this.photoUrls,
    required this.status,
    required this.acceptsOffers,
    required this.isLive,
    required this.createdAt,
    this.description,
    this.tags = const [],
  });

  factory CustomListingDetail.fromJson(Map<String, dynamic> json) {
    return CustomListingDetail(
      id: (json['id'] as num).toInt(),
      slug: json['slug'] as String? ?? '',
      sellerId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: (json['description'] as String?)?.trim(),
      // A draft has no price yet; only its owner can open one.
      price: (json['price'] as num?)?.toInt() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      qtyLocked: (json['qty_locked'] as num?)?.toInt() ?? 0,
      photoUrls: ((json['photo_urls'] as List?) ?? const [])
          .whereType<String>()
          .map(proxyImageUrl)
          .whereType<String>()
          .toList(),
      status: json['status'] as String? ?? 'open',
      acceptsOffers: json['accepts_offers'] as bool? ?? false,
      isLive: json['is_live'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      tags: [
        for (final tag in (json['tags'] as List?) ?? const [])
          if (tag is Map<String, dynamic>) CustomTaggedCard.fromJson(tag),
      ],
    );
  }

  final int id;
  final String slug;
  final String sellerId;
  final String title;
  final String? description;
  final int price;
  final int quantity;
  final int qtyLocked;
  final List<String> photoUrls;

  /// `draft`, `open`, or whatever closed it — a non-owner only ever sees
  /// `open`.
  final String status;
  final bool acceptsOffers;

  /// Open, not archived and not past its expiry — what a buyer can buy.
  final bool isLive;
  final DateTime createdAt;
  final List<CustomTaggedCard> tags;

  /// What a buyer can actually purchase.
  int get available => (quantity - qtyLocked).clamp(0, quantity);

  bool get hasDescription => description != null && description!.isNotEmpty;

  /// The listing as the cart, offer and chat code take it, sold by [store].
  ListingModel toListing(StoreModel store) => ListingModel(
    id: id,
    slug: slug,
    sellerId: sellerId,
    side: ListingSide.ask,
    price: price,
    // A custom listing is graded by nobody; every screen that draws a grade
    // checks `card.hasCondition` first.
    condition: CardCondition.nm,
    // Nothing to buy once it is not live: `get_custom_listing` still shows an
    // expired listing to a buyer, and a panel with stock would offer to add it.
    quantity: isLive ? quantity : qtyLocked,
    qtyLocked: qtyLocked,
    card: CardModel.custom(title: title, imageUrl: photoUrls.firstOrNull),
    storeSlug: store.handle,
    storeName: store.storeName,
    sellerUsername: store.username,
    isVerified: store.isVerified,
    cityName: store.cityName,
    createdAt: createdAt,
    acceptsOffers: acceptsOffers,
    photoUrls: photoUrls,
    storeLogoUrl: store.logoUrl,
    sellerAvatarUrl: store.avatarUrl,
  );
}
