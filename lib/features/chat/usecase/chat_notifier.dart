import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/chat_repository.dart';
import '../repository/models/chat_models.dart';

final chatRepositoryProvider = Provider((ref) => ChatRepository());

final chatThreadsProvider = FutureProvider<List<ChatThread>>((ref) {
  return ref.read(chatRepositoryProvider).fetchThreads();
});

class ChatMessagesNotifier extends FamilyNotifier<List<ChatMessage>, String> {
  @override
  List<ChatMessage> build(String arg) {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final messages = await ref.read(chatRepositoryProvider).fetchMessages(arg);
    state = messages;
  }

  void send(String text) {
    if (text.trim().isEmpty) return;
    state = [
      ...state,
      ChatMessage(
        id: state.length + 1,
        fromMe: true,
        text: text.trim(),
        sentAt: 'Baru saja',
      ),
    ];
  }
}

final chatMessagesProvider =
    NotifierProvider.family<ChatMessagesNotifier, List<ChatMessage>, String>(
      ChatMessagesNotifier.new,
    );
