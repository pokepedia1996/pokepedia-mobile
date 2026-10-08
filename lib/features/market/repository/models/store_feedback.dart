/// A seller's feedback, as the storefront's Penilaian tab shows it.
///
/// Two sources, as on web: `get_feedback_counts_matrix` for the summary (it
/// buckets by period server-side) and `get_feedback_list` for the reviews.
class StoreFeedbackSummary {
  const StoreFeedbackSummary({
    required this.positive,
    required this.neutral,
    required this.negative,
  });

  factory StoreFeedbackSummary.fromMatrix(
    Map<String, dynamic> matrix, {
    String period = 'all',
  }) {
    int read(String key) {
      final bucket = matrix[key];
      if (bucket is! Map) return 0;
      return (bucket[period] as num?)?.toInt() ?? 0;
    }

    return StoreFeedbackSummary(
      positive: read('positive'),
      neutral: read('neutral'),
      negative: read('negative'),
    );
  }

  final int positive;
  final int neutral;
  final int negative;

  int get total => positive + neutral + negative;

  /// Web's headline number. Null rather than 100% when nobody has rated:
  /// a perfect score from no reviews would be a lie.
  double? get positivePercent => total == 0 ? null : (positive / total) * 100;
}

enum FeedbackKind { positive, neutral, negative }

extension FeedbackKindX on FeedbackKind {
  static FeedbackKind fromRaw(String? raw) => switch (raw) {
    'positive' => FeedbackKind.positive,
    'negative' => FeedbackKind.negative,
    _ => FeedbackKind.neutral,
  };

  String get label => switch (this) {
    FeedbackKind.positive => 'Positif',
    FeedbackKind.neutral => 'Netral',
    FeedbackKind.negative => 'Negatif',
  };
}

/// One review left on a seller — a `get_feedback_list` row, which stands for
/// a whole transaction: its `feedback` is the worst tone across the order's
/// items and `is_auto` is true only when every item was auto-rated.
class StoreFeedback {
  const StoreFeedback({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.comment,
    this.reply,
    this.raterUsername,
    this.isAuto = false,
  });

  factory StoreFeedback.fromRow(Map<String, dynamic> row) {
    return StoreFeedback(
      id: (row['id'] as num).toInt(),
      kind: FeedbackKindX.fromRaw(row['feedback'] as String?),
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      comment: row['comment'] as String?,
      reply: row['reply'] as String?,
      raterUsername: row['rater_username'] as String?,
      isAuto: row['is_auto'] as bool? ?? false,
    );
  }

  /// The `rows` of a `get_feedback_list` payload (`{total, rows}`). Anything
  /// else — an error body, a null — reads as no reviews.
  static List<StoreFeedback> parseList(Object? payload) {
    if (payload is! Map) return const [];
    final rows = payload['rows'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .where((row) => row['id'] is num)
        .map(StoreFeedback.fromRow)
        .toList();
  }

  final int id;
  final FeedbackKind kind;
  final DateTime createdAt;
  final String? comment;

  /// The seller's answer, when they left one.
  final String? reply;
  final String? raterUsername;

  /// Left by the system when the rating window closed, not by a person.
  final bool isAuto;
}
