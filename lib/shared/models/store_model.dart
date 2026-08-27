import '../../core/utils/image_url.dart';

/// A seller storefront, mirroring `public.seller_profiles` in
/// `supabase/migrations/00000000000000_baseline.sql`.
/// The first value that is neither null nor blank, or `''` when there is
/// none.
///
/// A blank `store_slug` is not null, so a plain `??` chain would let it win
/// and produce a handle that builds `/market/` — a path with no `:handle`
/// segment for the route to read.
String _firstPresent(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value;
  }
  return '';
}

class StoreModel {
  const StoreModel({
    required this.handle,
    required this.storeName,
    required this.tagline,
    required this.activeListingCount,
    required this.cityName,
    required this.isVerified,
    required this.topRated,
    required this.itemsSoldCount,
    required this.followersCount,
    this.vacationMode,
    this.vacationUntil,
    this.vacationMessage,
    this.userId,
    this.logoUrl,
    this.bannerUrl,
    this.aboutMarkdown,
    this.memberSince,
    this.isFollowing = false,
  });

  final String handle;
  final String storeName;
  final String tagline;
  final int activeListingCount;
  final String cityName;
  final bool isVerified;

  /// `seller_profiles.top_rated`.
  final bool topRated;

  /// `seller_profiles.items_sold_count`.
  final int itemsSoldCount;

  /// `seller_profiles.followers_count`.
  final int followersCount;

  /// `seller_profiles.vacation_mode` ('soft' | 'hard' | null).
  final String? vacationMode;
  final DateTime? vacationUntil;
  final String? vacationMessage;

  /// The seller's `auth.users` id — not part of the dummy-data shape, only
  /// populated once fetched from Supabase. Lets `fetchStoreListings` reuse
  /// an already-fetched store profile instead of re-resolving the slug.
  final String? userId;

  final String? logoUrl;

  /// `seller_profiles.store_banner_url` — the cover image the storefront
  /// leads with on the web.
  final String? bannerUrl;

  /// `about_md` — the seller's own description, markdown.
  final String? aboutMarkdown;

  /// When they joined, and whether the viewer already follows them. Both
  /// come back from `get_seller_storefront_by_slug`.
  final DateTime? memberSince;
  final bool isFollowing;

  bool get onVacation => vacationMode != null;

  /// Ports the `search_stores` RPC row (`lib/storefront/store-directory.ts`)
  /// — the "Toko" directory tab. Doesn't return `top_rated`, so that badge
  /// only ever shows on the detail page (`fromDetailRow`), same as web.
  factory StoreModel.fromDirectoryRow(Map<String, dynamic> row) {
    return StoreModel(
      handle: _firstPresent([
        row['store_slug'] as String?,
        row['handle'] as String?,
      ]),
      storeName: row['store_name'] as String? ?? 'Toko',
      tagline: row['store_tagline'] as String? ?? '',
      activeListingCount: (row['active_listing_count'] as num?)?.toInt() ?? 0,
      cityName: row['city_name'] as String? ?? '',
      isVerified: row['is_verified'] as bool? ?? false,
      topRated: false,
      itemsSoldCount: row['items_sold_count'] as int? ?? 0,
      followersCount: row['followers_count'] as int? ?? 0,
      vacationMode: row['vacation_mode'] as String?,
      userId: row['user_id'] as String?,
      logoUrl: proxyImageUrl(row['store_logo_url'] as String?),
    );
  }

  /// Ports the `get_seller_storefront_by_slug` /
  /// `get_seller_storefront_by_username` RPC row — a single store's full
  /// profile. Both return the same columns.
  factory StoreModel.fromDetailRow(
    Map<String, dynamic> row, {
    required int activeListingCount,
  }) {
    return StoreModel(
      // Falls through to the username: a store resolved that way has no
      // slug, and an empty handle here would make every link back to this
      // store point at nothing.
      handle: _firstPresent([
        row['store_slug'] as String?,
        row['username'] as String?,
      ]),
      storeName: row['store_name'] as String? ?? 'Toko',
      tagline: row['store_tagline'] as String? ?? '',
      activeListingCount: activeListingCount,
      cityName: row['city_name'] as String? ?? '',
      isVerified: row['is_verified'] as bool? ?? false,
      topRated: row['top_rated'] as bool? ?? false,
      itemsSoldCount: row['items_sold_count'] as int? ?? 0,
      followersCount: row['followers_count'] as int? ?? 0,
      vacationMode: row['vacation_mode'] as String?,
      vacationUntil: DateTime.tryParse(row['vacation_until'] as String? ?? ''),
      vacationMessage: row['vacation_message'] as String?,
      userId: row['user_id'] as String?,
      logoUrl: proxyImageUrl(row['store_logo_url'] as String?),
      bannerUrl: proxyImageUrl(row['store_banner_url'] as String?),
      aboutMarkdown: row['about_md'] as String?,
      memberSince: DateTime.tryParse(row['member_since'] as String? ?? ''),
      isFollowing: row['is_following'] as bool? ?? false,
    );
  }
}
