class ChatThread {
  const ChatThread({
    required this.slug,
    required this.otherUsername,
    required this.lastMessage,
    required this.lastAt,
    required this.unread,
  });

  final String slug;
  final String otherUsername;
  final String lastMessage;
  final String lastAt;
  final int unread;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromMe,
    required this.text,
    required this.sentAt,
  });

  final int id;
  final bool fromMe;
  final String text;
  final String sentAt;
}
