/// A saved "List" — a shareable, named set of cards. Mirrors `public.lists`
/// and the `UserList` shape `features/list/api/lists.ts` maps rows into.
class WantlistModel {
  const WantlistModel({
    required this.id,
    required this.name,
    required this.shareCode,
    required this.cardCount,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
  });

  /// `lists.id` is a uuid, not a serial.
  final String id;
  final String name;
  final String description;

  /// The handle behind `/list/<code>`, which is how a list is shared.
  final String shareCode;
  final int cardCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory WantlistModel.fromRow(Map<String, dynamic> row) {
    // `list_cards(count)` embeds as `[{count: n}]`.
    var cardCount = 0;
    final counts = row['list_cards'];
    if (counts is List && counts.isNotEmpty) {
      final first = counts.first;
      if (first is Map) cardCount = (first['count'] as num?)?.toInt() ?? 0;
    }

    return WantlistModel(
      id: row['id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      shareCode: row['share_code'] as String? ?? '',
      cardCount: cardCount,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
    );
  }
}
