import '../../../../core/utils/image_url.dart';
import '../../../../shared/models/card_condition.dart';

/// A custom listing that has one catalog card tagged on it — a row of
/// `get_card_custom_listings`, for that card's page.
class CardCustomListing {
  const CardCustomListing({
    required this.slug,
    required this.title,
    required this.price,
    required this.available,
    required this.tagCondition,
    required this.tagQuantity,
    required this.tagCount,
    this.coverUrl,
    this.storeSlug,
    this.storeName,
    this.username,
    this.cityName,
  });

  factory CardCustomListing.fromRow(Map<String, dynamic> row) =>
      CardCustomListing(
        slug: row['slug'] as String? ?? '',
        title: row['title'] as String? ?? 'Listing custom',
        price: (row['price'] as num?)?.toInt() ?? 0,
        available: (row['available'] as num?)?.toInt() ?? 0,
        coverUrl: proxyImageUrl(
          ((row['photo_urls'] as List?) ?? const [])
              .whereType<String>()
              .firstOrNull,
        ),
        tagCondition: CardConditionX.fromRaw(
          row['tag_condition'] as String? ?? 'NM',
        ),
        tagQuantity: (row['tag_quantity'] as num?)?.toInt() ?? 1,
        tagCount: (row['tag_count'] as num?)?.toInt() ?? 1,
        storeSlug: row['store_slug'] as String?,
        storeName: row['store_name'] as String?,
        username: row['username'] as String?,
        cityName: row['city_name'] as String?,
      );

  final String slug;
  final String title;
  final int price;
  final int available;
  final String? coverUrl;

  /// This card on that listing: its grade and how many copies.
  final CardCondition tagCondition;
  final int tagQuantity;

  /// Every card tagged on the listing, this one included.
  final int tagCount;
  final String? storeSlug;
  final String? storeName;
  final String? username;
  final String? cityName;

  /// The store's path segment, as web's `listingHref` picks it: its slug,
  /// else its owner's username.
  String? get handle {
    if (storeSlug case final slug? when slug.isNotEmpty) return slug;
    if (username case final name? when name.isNotEmpty) return name;
    return null;
  }
}
