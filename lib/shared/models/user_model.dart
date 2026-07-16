/// `profiles.role` check constraint.
enum ProfileRole { user, admin, contributor }

/// A public collector profile, mirroring `public.profiles` joined with
/// `public.user_reputation` in
/// `supabase/migrations/00000000000000_baseline.sql`.
class UserModel {
  const UserModel({
    required this.username,
    required this.bio,
    required this.collectionCount,
    required this.followerCount,
    required this.joinedAt,
    this.role = ProfileRole.user,
    this.isCollectionPublic = true,
    this.totalTrades = 0,
    this.positivePct,
  });

  final String username;
  final String bio;
  final int collectionCount;
  final int followerCount;
  final String joinedAt;

  /// `profiles.role`.
  final ProfileRole role;

  /// `profiles.is_collection_public`.
  final bool isCollectionPublic;

  /// `user_reputation.total_trades`.
  final int totalTrades;

  /// `user_reputation.positive_pct` (numeric(5,2), null until first trade).
  final double? positivePct;
}
