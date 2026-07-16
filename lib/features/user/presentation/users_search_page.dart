import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/models/user_model.dart';
import '../usecase/user_notifier.dart';

/// Ports `app/users/page.tsx`.
class UsersSearchPage extends ConsumerWidget {
  const UsersSearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(usersSearchProvider);
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Cari Pengguna')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (v) =>
                    ref.read(usersSearchQueryProvider.notifier).state = v,
                decoration: const InputDecoration(
                  hintText: 'Cari username...',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            Expanded(
              child: async.when(
                data: (users) {
                  if (users.isEmpty) {
                    return const EmptyState(
                      icon: Icons.person_search,
                      title: 'Pengguna tidak ditemukan',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: users.length,
                    separatorBuilder: (context, i) =>
                        Divider(height: 1, color: context.borderColor),
                    itemBuilder: (context, i) {
                      final user = users[i];
                      return _UserTile(user: user, colors: colors);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(child: Text('Gagal memuat pengguna')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.colors});

  final UserModel user;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(Routes.userProfile(user.username)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: colors.secondary,
              child: Text(
                user.username.substring(0, 1).toUpperCase(),
                style: AppTypography.bodySemibold(colors.onSurface),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.username, style: AppTypography.bodySmSemibold(colors.onSurface)),
                  Text(
                    '${user.collectionCount} kartu · ${user.followerCount} pengikut',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
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
