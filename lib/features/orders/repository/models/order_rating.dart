/// The three verdicts `submit_feedback` accepts.
///
/// Mirrors `FeedbackValue` in `lib/feedback/types.ts`. The market feature
/// already has a `FeedbackKind` for reading a store's reviews; this one is
/// the writing side, and carries the raw value the RPC expects.
enum FeedbackKind { positive, neutral, negative }

extension FeedbackKindX on FeedbackKind {
  String get raw => switch (this) {
    FeedbackKind.positive => 'positive',
    FeedbackKind.neutral => 'neutral',
    FeedbackKind.negative => 'negative',
  };

  String get label => switch (this) {
    FeedbackKind.positive => 'Positif',
    FeedbackKind.neutral => 'Netral',
    FeedbackKind.negative => 'Negatif',
  };

  static FeedbackKind fromRaw(String? raw) => switch (raw) {
    'positive' => FeedbackKind.positive,
    'negative' => FeedbackKind.negative,
    _ => FeedbackKind.neutral,
  };
}

/// A rating this buyer has already left on an order — web's `myFeedback`.
class OrderRating {
  const OrderRating({
    required this.id,
    required this.orderItemId,
    required this.feedback,
    required this.createdAt,
    this.comment,
    this.reply,
    this.replyAt,
  });

  factory OrderRating.fromRow(Map<String, dynamic> row) {
    return OrderRating(
      id: (row['id'] as num?)?.toInt() ?? 0,
      orderItemId: (row['order_item_id'] as num?)?.toInt() ?? 0,
      feedback: FeedbackKindX.fromRaw(row['feedback'] as String?),
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      comment: row['comment'] as String?,
      reply: row['reply'] as String?,
      replyAt: DateTime.tryParse(row['reply_at'] as String? ?? '')?.toLocal(),
    );
  }

  final int id;
  final int orderItemId;
  final FeedbackKind feedback;
  final DateTime createdAt;
  final String? comment;

  /// The seller's answer, shown under the review once they leave one.
  final String? reply;
  final DateTime? replyAt;
}
