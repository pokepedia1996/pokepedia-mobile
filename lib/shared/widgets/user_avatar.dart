import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Ports `components/auth/user-avatar.tsx` and the profile page's
/// `ProfileAvatar` — a circular avatar falling back to the first two
/// letters of the username, optionally inside the primary-tinted ring the
/// profile header uses.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.username,
    this.imageUrl,
    this.size = 40,
    this.ring = false,
  });

  final String username;
  final String? imageUrl;
  final double size;

  /// The `ring-3 ring-primary/20 ring-offset-2` treatment on the profile
  /// header's 80px avatar.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final initials = username.trim().isEmpty
        ? '?'
        : username.trim().substring(0, username.trim().length >= 2 ? 2 : 1).toUpperCase();

    Widget avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.secondary,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null || imageUrl!.isEmpty
          ? Text(
              initials,
              style: TextStyle(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w600,
                color: context.mutedForeground,
              ),
            )
          : Image.network(
              imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Text(
                initials,
                style: TextStyle(
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w600,
                  color: context.mutedForeground,
                ),
              ),
            ),
    );

    if (!ring) return avatar;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.primary.withValues(alpha: 0.2), width: 3),
      ),
      child: avatar,
    );
  }
}
