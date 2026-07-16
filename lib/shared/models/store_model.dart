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

  bool get onVacation => vacationMode != null;
}
