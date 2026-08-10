import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/card_grid_item.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../portfolio/usecase/portfolio_notifier.dart';
import '../usecase/user_notifier.dart';

/// Ports `app/user/[username]/page.tsx`.
class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.username});

  final String username;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userProfileProvider(widget.username));
    final collectionAsync = ref.watch(collectionProvider);
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}')),
      body: SafeArea(
        top: false,
        child: async.when(
          data: (user) {
            if (user == null) {
              return const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Pengguna tidak ditemukan',
              );
            }
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: colors.secondary,
                              child: Text(
                                user.username.substring(0, 1).toUpperCase(),
                                style: AppTypography.h2(colors.onSurface),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.username,
                                    style: AppTypography.h3(colors.onSurface),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    user.joinedAt,
                                    style: AppTypography.caption(
                                      context.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          user.bio,
                          style: AppTypography.bodySm(colors.onSurface),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 20,
                          runSpacing: 6,
                          children: [
                            _Stat(
                              label: 'Kartu',
                              value: '${user.collectionCount}',
                            ),
                            _Stat(
                              label: 'Pengikut',
                              value: '${user.followerCount}',
                            ),
                            _Stat(
                              label: 'Trading',
                              value: '${user.totalTrades}',
                            ),
                            if (user.positivePct != null)
                              _Stat(
                                label: 'Positif',
                                value: '${user.positivePct}%',
                              ),
                          ],
                        ),
                        if (user.role != ProfileRole.user) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                AppRadius.full,
                              ),
                            ),
                            child: Text(
                              user.role == ProfileRole.admin
                                  ? 'Admin'
                                  : 'Kontributor',
                              style: AppTypography.captionSemibold(
                                colors.primary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: _following
                              ? OutlinedButton(
                                  onPressed: () =>
                                      setState(() => _following = false),
                                  child: const Text('Mengikuti'),
                                )
                              : ElevatedButton(
                                  onPressed: () =>
                                      setState(() => _following = true),
                                  child: const Text('Ikuti'),
                                ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Koleksi Unggulan',
                          style: AppTypography.h3(colors.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
                collectionAsync.when(
                  data: (cards) => SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.62,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) =>
                            CardGridItem(card: cards[i], onTap: () {}),
                        childCount: cards.length > 6 ? 6 : cards.length,
                      ),
                    ),
                  ),
                  loading: () =>
                      const SliverToBoxAdapter(child: PikachuLoader()),
                  error: (_, __) =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
              ],
            );
          },
          loading: () => const PikachuLoader(),
          error: (_, __) => const EmptyState(
            icon: Icons.error_outline,
            title: 'Gagal memuat profil',
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: AppTypography.bodySemibold(context.appColors.onSurface),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.caption(context.mutedForeground)),
      ],
    );
  }
}
