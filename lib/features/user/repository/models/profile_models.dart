import '../../../../core/utils/image_url.dart';

/// A public collector profile, ported from `PublicProfile` in
/// `pokepedia-web/lib/user/profile.ts` (the `get_public_profile` RPC).
class PublicProfile {
  const PublicProfile({
    required this.userId,
    required this.username,
    required this.isCollectionPublic,
    required this.showCollectionQuantity,
    required this.contributionCount,
    this.avatarUrl,
    this.bio,
    this.socialWhatsapp,
    this.socialFacebook,
    this.socialInstagram,
    this.socialTiktok,
    this.socialX,
  });

  final String userId;
  final String username;
  final bool isCollectionPublic;
  final bool showCollectionQuantity;
  final int contributionCount;
  final String? avatarUrl;
  final String? bio;

  /// Only readable by signed-in viewers — comes from `get_seller_contact`
  /// rather than the profile row itself.
  final String? socialWhatsapp;
  final String? socialFacebook;
  final String? socialInstagram;
  final String? socialTiktok;
  final String? socialX;

  bool get hasSocials =>
      socialWhatsapp != null ||
      socialFacebook != null ||
      socialInstagram != null ||
      socialTiktok != null ||
      socialX != null;

  PublicProfile copyWith({
    String? Function()? socialWhatsapp,
    bool? isCollectionPublic,
    bool? showCollectionQuantity,
  }) {
    return PublicProfile(
      userId: userId,
      username: username,
      isCollectionPublic: isCollectionPublic ?? this.isCollectionPublic,
      showCollectionQuantity:
          showCollectionQuantity ?? this.showCollectionQuantity,
      contributionCount: contributionCount,
      avatarUrl: avatarUrl,
      bio: bio,
      socialWhatsapp: socialWhatsapp == null
          ? this.socialWhatsapp
          : socialWhatsapp(),
      socialFacebook: socialFacebook,
      socialInstagram: socialInstagram,
      socialTiktok: socialTiktok,
      socialX: socialX,
    );
  }

  static String? _blankToNull(dynamic value) {
    final text = value as String?;
    return (text == null || text.trim().isEmpty) ? null : text.trim();
  }

  factory PublicProfile.fromRow(Map<String, dynamic> row) {
    return PublicProfile(
      userId: row['id'] as String? ?? '',
      username: row['username'] as String? ?? '',
      isCollectionPublic: row['is_collection_public'] as bool? ?? false,
      showCollectionQuantity: row['show_collection_quantity'] as bool? ?? true,
      contributionCount: (row['contribution_count'] as num?)?.toInt() ?? 0,
      avatarUrl: proxyImageUrl(row['avatar_url'] as String?),
      bio: _blankToNull(row['bio']),
      socialFacebook: _blankToNull(row['social_facebook']),
      socialInstagram: _blankToNull(row['social_instagram']),
      socialTiktok: _blankToNull(row['social_tiktok']),
      socialX: _blankToNull(row['social_x']),
    );
  }
}

/// The signed-in user's own private contact row (`profiles_private`), read
/// by the settings screen for the phone-verification state.
class PrivateProfile {
  const PrivateProfile({
    this.phone,
    this.phoneVerified = false,
    this.socialWhatsapp,
  });

  final String? phone;
  final bool phoneVerified;
  final String? socialWhatsapp;

  factory PrivateProfile.fromRow(Map<String, dynamic>? row) {
    if (row == null) return const PrivateProfile();
    return PrivateProfile(
      phone: row['phone'] as String?,
      phoneVerified: row['phone_verified_at'] != null,
      socialWhatsapp: row['social_whatsapp'] as String?,
    );
  }
}

/// A card whose artwork this user contributed (an approved
/// `card_image_submissions` row).
class ContributionCardEntry {
  const ContributionCardEntry({
    required this.cardId,
    required this.name,
    required this.number,
    required this.expansionCode,
    this.imageUrl,
  });

  final int cardId;
  final String name;
  final String number;
  final String expansionCode;
  final String? imageUrl;

  String get packSlug => expansionCode.toLowerCase();
}

/// One row of the user directory, ported from `UserSearchResult`.
class UserSearchResult {
  const UserSearchResult({
    required this.username,
    required this.contributionCount,
    this.avatarUrl,
  });

  final String username;
  final int contributionCount;
  final String? avatarUrl;
}

/// A listing thumbnail shown under a followed shop.
class FollowedShopListing {
  const FollowedShopListing({
    required this.cardId,
    required this.price,
    this.photoUrl,
  });

  final int cardId;
  final int price;
  final String? photoUrl;
}

/// One row of the `get_followed_shops` RPC — the cards on
/// `app/account/following/page.tsx`.
class FollowedShop {
  const FollowedShop({
    required this.shopUserId,
    required this.name,
    required this.slug,
    required this.followersCount,
    required this.itemsSoldCount,
    required this.recentListings,
    this.logoUrl,
    this.bannerUrl,
    this.cityName,
  });

  final String shopUserId;

  /// Store name, falling back to the owner's username — web's
  /// `resolveSellerDisplay`.
  final String name;

  /// Store slug, falling back to the username, used for the shop route.
  final String slug;
  final int followersCount;
  final int itemsSoldCount;
  final List<FollowedShopListing> recentListings;
  final String? logoUrl;
  final String? bannerUrl;
  final String? cityName;

  /// Null when the row has neither a store slug nor a username, which is
  /// the case web's `resolveSellerDisplay` returns no href for.
  static FollowedShop? fromRow(Map<String, dynamic> row) {
    final storeSlug = row['store_slug'] as String?;
    final username = row['username'] as String?;
    final slug = (storeSlug != null && storeSlug.isNotEmpty)
        ? storeSlug
        : (username != null && username.isNotEmpty ? username : null);
    if (slug == null) return null;

    final storeName = row['store_name'] as String?;
    final listings = (row['recent_listings'] as List?) ?? const [];

    return FollowedShop(
      shopUserId: row['shop_user_id'] as String? ?? '',
      name: (storeName != null && storeName.isNotEmpty)
          ? storeName
          : (username ?? 'Toko'),
      slug: slug,
      followersCount: (row['followers_count'] as num?)?.toInt() ?? 0,
      itemsSoldCount: (row['items_sold_count'] as num?)?.toInt() ?? 0,
      logoUrl: proxyImageUrl(
        row['store_logo_url'] as String? ?? row['avatar_url'] as String?,
      ),
      bannerUrl: proxyImageUrl(row['store_banner_url'] as String?),
      cityName: row['city_name'] as String?,
      recentListings: listings.whereType<Map<String, dynamic>>().take(4).map((
        l,
      ) {
        final photos = (l['photo_urls'] as List?) ?? const [];
        final photo = photos.whereType<String>().isEmpty
            ? null
            : photos.whereType<String>().first;
        return FollowedShopListing(
          cardId: (l['card_id'] as num?)?.toInt() ?? 0,
          price: (l['price'] as num?)?.toInt() ?? 0,
          photoUrl: proxyImageUrl(photo),
        );
      }).toList(),
    );
  }
}
