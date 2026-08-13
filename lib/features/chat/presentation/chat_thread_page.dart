import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../usecase/chat_notifier.dart';

/// Ports `components/chat/chat-room.tsx`.
class ChatThreadPage extends ConsumerStatefulWidget {
  const ChatThreadPage({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends ConsumerState<ChatThreadPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider(widget.slug));
    final colors = context.appColors;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, i) {
                  final message = messages[messages.length - 1 - i];
                  return Align(
                    alignment: message.fromMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      constraints: const BoxConstraints(maxWidth: 260),
                      decoration: BoxDecoration(
                        color: message.fromMe
                            ? colors.primary
                            : colors.secondary,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.text,
                            style: AppTypography.bodySm(
                              message.fromMe
                                  ? colors.onPrimary
                                  : colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            message.sentAt,
                            style: AppTypography.caption(
                              message.fromMe
                                  ? colors.onPrimary.withValues(alpha: 0.7)
                                  : context.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Tulis pesan...',
                      ),
                      onSubmitted: (v) {
                        ref
                            .read(chatMessagesProvider(widget.slug).notifier)
                            .send(v);
                        _controller.clear();
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: colors.primary),
                    onPressed: () {
                      ref
                          .read(chatMessagesProvider(widget.slug).notifier)
                          .send(_controller.text);
                      _controller.clear();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
