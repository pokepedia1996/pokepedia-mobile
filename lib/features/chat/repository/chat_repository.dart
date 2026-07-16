import 'models/chat_models.dart';

/// Data access for the Chat feature. Stands in for the web's realtime
/// Supabase chat channels while this pass only ports the UI with dummy
/// data.
class ChatRepository {
  static final List<ChatThread> _threads = [
    const ChatThread(
      slug: 'cardvault-id',
      otherUsername: 'Card Vault ID',
      lastMessage: 'Kartu sudah dikemas, siap dikirim besok pagi ya kak',
      lastAt: '10:24',
      unread: 2,
    ),
    const ChatThread(
      slug: 'pokecorner',
      otherUsername: 'Poke Corner',
      lastMessage: 'Boleh nego dikit gak kak buat 2 pcs?',
      lastAt: 'Kemarin',
      unread: 0,
    ),
    const ChatThread(
      slug: 'trainerhub',
      otherUsername: 'Trainer Hub',
      lastMessage: 'Terima kasih sudah belanja di toko kami!',
      lastAt: '2 hari lalu',
      unread: 0,
    ),
  ];

  static final Map<String, List<ChatMessage>> _messages = {
    'cardvault-id': [
      const ChatMessage(id: 1, fromMe: true, text: 'Halo kak, masih ready?', sentAt: '09:58'),
      const ChatMessage(id: 2, fromMe: false, text: 'Ready kak, langsung checkout aja ya', sentAt: '10:01'),
      const ChatMessage(id: 3, fromMe: true, text: 'Oke sudah aku bayar', sentAt: '10:10'),
      const ChatMessage(id: 4, fromMe: false, text: 'Kartu sudah dikemas, siap dikirim besok pagi ya kak', sentAt: '10:24'),
    ],
    'pokecorner': [
      const ChatMessage(id: 1, fromMe: false, text: 'Boleh nego dikit gak kak buat 2 pcs?', sentAt: 'Kemarin'),
    ],
    'trainerhub': [
      const ChatMessage(id: 1, fromMe: false, text: 'Terima kasih sudah belanja di toko kami!', sentAt: '2 hari lalu'),
    ],
  };

  Future<List<ChatThread>> fetchThreads() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _threads;
  }

  Future<List<ChatMessage>> fetchMessages(String slug) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _messages[slug] ?? const [];
  }
}
