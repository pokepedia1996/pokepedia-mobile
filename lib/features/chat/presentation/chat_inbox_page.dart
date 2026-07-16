import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../repository/models/chat_models.dart';
import '../usecase/chat_notifier.dart';

/// Ports `components/chat/ConversationList.tsx` / `app/chat/page.tsx`.
class ChatInboxPage extends ConsumerWidget {
  const ChatInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chatThreadsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pesan')),
      body: SafeArea(
        top: false,
        child: async.when(
          data: (threads) {
            if (threads.isEmpty) {
              return const EmptyState(
                icon: Icons.chat_bubble_outline,
                title: 'Belum ada percakapan',
              );
            }
            return ListView.separated(
              itemCount: threads.length,
              separatorBuilder: (context, i) =>
                  Divider(height: 1, color: context.borderColor, indent: 76),
              itemBuilder: (context, i) => _ThreadTile(thread: threads[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Gagal memuat pesan')),
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
      onTap: () => context.push(Routes.chatThread(thread.slug)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: colors.secondary,
              child: Text(
                thread.otherUsername.substring(0, 1).toUpperCase(),
                style: AppTypography.bodySemibold(colors.onSurface),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.otherUsername,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    thread.lastMessage,
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
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${thread.unread}',
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
