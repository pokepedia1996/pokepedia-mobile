import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../repository/models/chat_models.dart';
import '../usecase/chat_notifier.dart';

/// Ports `components/chat/ConversationList.tsx` / `app/chat/page.tsx`, backed
/// by `get_chat_room_summaries`.
class ChatInboxPage extends ConsumerWidget {
  const ChatInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authProvider).valueOrNull != null;
    final async = ref.watch(chatThreadsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pesan')),
      body: !signedIn
          ? EmptyState(
              icon: LucideIcons.messageCircle,
              title: 'Masuk untuk melihat pesan',
              action: ElevatedButton(
                onPressed: () => context.push(Routes.login),
                child: const Text('Masuk'),
              ),
            )
          : async.when(
              data: (threads) {
                if (threads.isEmpty) {
                  return const EmptyState(
                    icon: LucideIcons.messageCircle,
                    title: 'Belum ada percakapan',
                    description:
                        'Percakapan muncul di sini setelah kamu menghubungi penjual.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(chatThreadsProvider),
                  child: ListView.separated(
                    itemCount: threads.length,
                    separatorBuilder: (context, i) => Divider(
                      height: 1,
                      color: context.borderColor,
                      indent: 76,
                    ),
                    itemBuilder: (context, i) =>
                        _ThreadTile(thread: threads[i]),
                  ),
                );
              },
              loading: () => const PikachuLoader(),
              error: (_, __) => EmptyState(
                icon: LucideIcons.circleAlert,
                title: 'Gagal memuat pesan',
                action: OutlinedButton(
                  onPressed: () => ref.invalidate(chatThreadsProvider),
                  child: const Text('Coba lagi'),
                ),
              ),
            ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread});

  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final unread = thread.unread > 0;

    return InkWell(
      // The name rides along so the thread's bar can show it immediately,
      // instead of "Percakapan" until the room resolves.
      onTap: () => context.push(
        Routes.chatThread(thread.slug),
        extra: thread.displayName,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            UserAvatar(
              username: thread.displayName,
              imageUrl: thread.otherAvatarUrl,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    thread.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: unread
                        ? AppTypography.bodySmSemibold(colors.onSurface)
                        : AppTypography.bodySm(context.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  thread.lastAt,
                  style: AppTypography.caption(context.mutedForeground),
                ),
                if (unread) ...[
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      thread.unread > 99 ? '99+' : '${thread.unread}',
                      style: AppTypography.badge(colors.onPrimary),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
