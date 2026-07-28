import '../../core/utils/image_url.dart';

/// A seller storefront, mirroring `public.seller_profiles` in
/// `supabase/migrations/00000000000000_baseline.sql`.
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

  bool get onVacation => vacationMode != null;

  /// Ports the `search_stores` RPC row (`lib/storefront/store-directory.ts`)
  /// — the "Toko" directory tab. Doesn't return `top_rated`, so that badge
  /// only ever shows on the detail page (`fromDetailRow`), same as web.
  factory StoreModel.fromDirectoryRow(Map<String, dynamic> row) {
    return StoreModel(
      handle: row['store_slug'] as String? ?? row['handle'] as String? ?? '',
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

  /// Ports the `get_seller_storefront_by_slug` RPC row — a single store's
  /// full profile.
  factory StoreModel.fromDetailRow(Map<String, dynamic> row, {required int activeListingCount}) {
    return StoreModel(
      handle: row['store_slug'] as String? ?? '',
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
    );
  }
}
