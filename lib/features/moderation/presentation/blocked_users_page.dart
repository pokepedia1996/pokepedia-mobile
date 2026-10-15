import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../settings/presentation/settings_page.dart' show SettingsSection;
import '../usecase/moderation_notifier.dart';

/// Ports web's Pengaturan › Pengguna diblokir tab (`blocked-users-list.tsx`).
///
/// The one place a blocker can undo a block made from a chat: the server
/// drops a blocked room from both inboxes, so the chat itself is gone.
class BlockedUsersPage extends ConsumerWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsSection(
              title: 'Pengguna diblokir',
              description:
                  'Kamu dan pengguna ini tidak bisa saling chat atau melihat '
                  'profil, toko, dan listing.',
              children: [
                blocked.when(
                  data: (users) => users.isEmpty
                      ? const EmptyState(
                          icon: LucideIcons.shieldCheck,
                          title: 'Kamu belum memblokir siapa pun.',
                        )
                      : _BlockedList(users: users),
                  loading: () => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Memuat…',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySm(context.mutedForeground),
                    ),
                  ),
                  error: (_, __) => const EmptyState(
                    icon: LucideIcons.circleAlert,
                    title: 'Gagal memuat daftar blokir.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedList extends ConsumerStatefulWidget {
  const _BlockedList({required this.users});

  final List<BlockedUser> users;

  @override
  ConsumerState<_BlockedList> createState() => _BlockedListState();
}

class _BlockedListState extends ConsumerState<_BlockedList> {
  /// Web disables every row's button while one unblock is in flight.
  String? _pending;

  Future<void> _unblock(BlockedUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending = user.userId);
    try {
      await setUserBlocked(ref, user.userId, false);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Blokir dibuka')));
    } on ModerationException catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        for (final user in widget.users)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                UserAvatar(
                  username: user.username ?? 'Pengguna',
                  imageUrl: user.avatarUrl,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: user.username == null
                        ? null
                        : () =>
                              context.push(Routes.userProfile(user.username!)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        if (user.storeName != null)
                          Text(
                            user.storeName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: _pending != null ? null : () => _unblock(user),
                  child: Text(
                    _pending == user.userId ? 'Membuka…' : 'Buka blokir',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
