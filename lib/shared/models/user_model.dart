import '../../core/utils/formatters.dart';

/// `profiles.role` check constraint.
enum ProfileRole { user, admin, contributor }

ProfileRole _roleFromRaw(String? raw) {
  switch (raw) {
    case 'admin':
      return ProfileRole.admin;
    case 'contributor':
      return ProfileRole.contributor;
    case 'user':
    default:
      return ProfileRole.user;
  }
}

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
    this.isCollectionPublic = false,
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

  /// Maps a `profiles` row optionally merged with its `user_reputation`
  /// counterpart. `collectionCount`/`followerCount` have no source column
  /// yet (they need the portfolio/inventory and shop-follows domains,
  /// which are out of scope for this pass) and default to 0.
  factory UserModel.fromRow(Map<String, dynamic> row) {
    final createdAtRaw = row['created_at'] as String?;
    final createdAt = createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw);
    final positivePctRaw = row['positive_pct'];
    return UserModel(
      username: row['username'] as String? ?? '',
      bio: row['bio'] as String? ?? '',
      collectionCount: 0,
      followerCount: 0,
      joinedAt: createdAt == null ? '' : formatJoinedId(createdAt),
      role: _roleFromRaw(row['role'] as String?),
      isCollectionPublic: row['is_collection_public'] as bool? ?? false,
      totalTrades: row['total_trades'] as int? ?? 0,
      positivePct: positivePctRaw == null ? null : (positivePctRaw as num).toDouble(),
    );
  }
}
