import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../repository/models/profile_models.dart';
import '../usecase/user_notifier.dart';

/// Ports `app/users/page.tsx` — the user directory: a debounced username
/// search that only runs from two characters up, with the contributor badge
/// on each result.
class UsersSearchPage extends ConsumerWidget {
  const UsersSearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final query = ref.watch(usersSearchQueryProvider);
    final async = ref.watch(usersSearchProvider);
    final searched = query.trim().length >= 2;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.people_outline, size: 22, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Cari Pengguna',
                        style: AppTypography.h2(colors.onSurface),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Temukan pengguna dan lihat koleksi kartu mereka',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) =>
                        ref.read(usersSearchQueryProvider.notifier).state =
                            value,
                    decoration: const InputDecoration(
                      hintText: 'Cari berdasarkan username...',
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !searched
                  ? _Hint(
                      icon: Icons.people_outline,
                      message: 'Ketik minimal 2 karakter untuk mencari',
                    )
                  : async.when(
                      data: (users) {
                        if (users.isEmpty) {
                          return _Hint(
                            icon: Icons.search_off,
                            message:
                                'Tidak ada pengguna ditemukan untuk "${query.trim()}"',
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: users.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) =>
                              _UserCard(user: users[i]),
                        );
                      },
                      loading: () => const _ResultsPlaceholder(),
                      error: (_, __) => _Hint(
                        icon: Icons.error_outline,
                        message: 'Gagal memuat pengguna',
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final UserSearchResult user;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => context.push(Routes.userProfile(user.username)),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: context.borderColor),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            UserAvatar(
              username: user.username,
              imageUrl: user.avatarUrl,
              size: 48,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySemibold(colors.onSurface),
                  ),
                  if (user.contributionCount > 0) ...[
                    const SizedBox(height: 2),
                    ContributorBadge(count: user.contributionCount),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.mutedForeground),
          ],
        ),
      ),
    );
  }
}

/// The "Kontributor · N kartu" line web shows in red on both the directory
/// and the profile header.
class ContributorBadge extends StatelessWidget {
  const ContributorBadge({super.key, required this.count, this.large = false});

  final int count;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.workspace_premium_outlined, size: large ? 16 : 13, color: color),
        const SizedBox(width: 4),
        Text(
          'Kontributor · $count kartu',
          style: large
              ? AppTypography.bodySmSemibold(color)
              : AppTypography.captionSemibold(color),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 40,
            color: context.mutedForeground.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _ResultsPlaceholder extends StatelessWidget {
  const _ResultsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, _) => Container(
        height: 72,
        decoration: BoxDecoration(
          color: context.appColors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}
