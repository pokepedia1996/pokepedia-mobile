/// A seller's feedback, as the storefront's Penilaian tab shows it.
///
/// Two sources: `get_feedback_counts_matrix` for the summary (it buckets by
/// period server-side) and `trade_ratings` for the reviews themselves —
/// `get_feedback_list` exists in the web repo but isn't deployed to this
/// project, and `ratings_select_public` makes the rows readable anyway.
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

/// One review left on a seller.
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

  factory StoreFeedback.fromRow(
    Map<String, dynamic> row, {
    String? raterUsername,
  }) {
    return StoreFeedback(
      id: (row['id'] as num).toInt(),
      kind: FeedbackKindX.fromRaw(row['feedback'] as String?),
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      comment: row['comment'] as String?,
      reply: row['reply'] as String?,
      raterUsername: raterUsername,
      isAuto: row['is_auto'] as bool? ?? false,
    );
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
