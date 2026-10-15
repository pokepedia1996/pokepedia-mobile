import '../../../../core/utils/image_url.dart';

/// One row of `get_blocked_users`: someone the caller blocked. The profile
/// and store fields come from LEFT JOINs, so any of them can be missing.
class BlockedUser {
  const BlockedUser({
    required this.userId,
    required this.blockedAt,
    this.username,
    this.avatarUrl,
    this.storeName,
    this.storeSlug,
  });

  factory BlockedUser.fromRow(Map<String, dynamic> row) => BlockedUser(
    userId: row['user_id'] as String,
    username: row['username'] as String?,
    avatarUrl: proxyImageUrl(row['avatar_url'] as String?),
    storeName: row['store_name'] as String?,
    storeSlug: row['store_slug'] as String?,
    blockedAt:
        DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );

  final String userId;
  final String? username;
  final String? avatarUrl;
  final String? storeName;
  final String? storeSlug;
  final DateTime blockedAt;

  /// `@username`, or web's "Pengguna" when the profile is gone.
  String get handle => username == null ? 'Pengguna' : '@$username';
}

/// `get_block_status`: whether the caller blocked the user behind a handle.
///
/// Says nothing about being blocked *by* them — the RPC deliberately makes
/// that look the same as a user who doesn't exist.
class BlockStatus {
  const BlockStatus({required this.blockedByMe, this.userId, this.username});

  factory BlockStatus.fromJson(Object? data) {
    if (data is! Map) return const BlockStatus(blockedByMe: false);
    return BlockStatus(
      blockedByMe: data['blocked_by_me'] == true,
      userId: data['user_id'] as String?,
      username: data['username'] as String?,
    );
  }

  final bool blockedByMe;
  final String? userId;
  final String? username;
}
