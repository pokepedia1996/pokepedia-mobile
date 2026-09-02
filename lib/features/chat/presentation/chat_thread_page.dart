import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../repository/chat_repository.dart';
import '../repository/models/chat_models.dart';
import '../usecase/chat_notifier.dart';

/// Ports `components/chat/chat-room.tsx`, backed by `chat_messages` with a
/// realtime subscription for the other side's replies.
///
/// Opens in one of two states: an existing room (by [slug]), or a
/// conversation with a [target] that has no room yet — rooms are created
/// lazily by `ensure_direct_room` on the first message.
class ChatThreadPage extends ConsumerStatefulWidget {
  const ChatThreadPage({super.key, this.slug, this.target, this.titleHint});

  final String? slug;
  final ChatTarget? target;

  /// The name the caller already knows, shown until the room resolves.
  final String? titleHint;

  @override
  ConsumerState<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  late final ChatThreadArg _arg = (
    slug: widget.slug,
    otherUserId: widget.target?.otherUserId,
    listingId: widget.target?.listingId,
    title: widget.target?.title ?? widget.titleHint ?? 'Percakapan',
  );

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    try {
      await ref.read(chatThreadProvider(_arg).notifier).send(text);
    } on ChatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Pesan gagal dikirim')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(chatThreadProvider(_arg));
    final state = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state?.title ?? _arg.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: async.when(
        loading: () => const PikachuLoader(),
        error: (_, __) => const EmptyState(
          icon: LucideIcons.circleAlert,
          title: 'Gagal memuat percakapan',
        ),
        data: (state) {
          if (state.missing || (widget.slug == null && widget.target == null)) {
            return const EmptyState(
              icon: LucideIcons.messageCircle,
              title: 'Percakapan tidak ditemukan',
              description: 'Percakapan ini mungkin sudah dihapus.',
            );
          }
          return Column(
            children: [
              Expanded(
                child: state.messages.isEmpty
                    ? EmptyState(
                        icon: LucideIcons.messageCircle,
                        title: 'Mulai percakapan',
                        description: 'Kirim pesan pertamamu ke ${state.title}.',
                      )
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: state.messages.length,
                        itemBuilder: (context, i) => _Bubble(
                          message:
                              state.messages[state.messages.length - 1 - i],
                        ),
                      ),
              ),
              _Composer(
                controller: _controller,
                sending: state.sending,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // Room events (`listing_context`, `order_event`, …) are notes about the
    // conversation, not speech in it.
    if (message.isEvent) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              message.text.isEmpty ? 'Pembaruan percakapan' : message.text,
              textAlign: TextAlign.center,
              style: AppTypography.caption(context.mutedForeground),
            ),
          ),
        ),
      );
    }

    final mine = message.fromMe;
    final foreground = mine ? colors.onPrimary : colors.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: mine ? colors.primary : colors.secondary,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: message.failed
              ? Border.all(color: colors.error, width: 1)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text, style: AppTypography.bodySm(foreground)),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // A pending bubble has no server timestamp worth showing,
                  // and a failed one needs saying plainly.
                  message.failed
                      ? 'Gagal terkirim'
                      : message.pending
                      ? 'Mengirim...'
                      : message.sentAt,
                  style: AppTypography.caption(
                    message.failed
                        ? colors.error
                        : mine
                        ? colors.onPrimary.withValues(alpha: 0.7)
                        : context.mutedForeground,
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(top: BorderSide(color: context.borderColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Tulis pesan...'),
                onSubmitted: (_) => onSend(),
              ),
            ),
            IconButton(
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(LucideIcons.send, color: colors.primary),
              onPressed: sending ? null : onSend,
            ),
          ],
        ),
      ),
    );
  }
}
