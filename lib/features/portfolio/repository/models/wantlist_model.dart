/// A saved collection — a named set of cards. Mirrors `public.collections`
/// and the shape `features/collection/api` maps rows into on the web.
///
/// The primary collection (the one that replaced `user_cards`) is a row in
/// this same table; the lists screen only ever shows the non-primary ones,
/// so nothing here carries `is_primary`.
class WantlistModel {
  const WantlistModel({
    required this.id,
    required this.name,
    required this.slug,
    required this.cardCount,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.isPublic = false,
  });

  /// `collections.id` is a uuid, not a serial.
  final String id;
  final String name;
  final String description;

  /// The handle behind `/u/<username>/<slug>`, which is how a collection is
  /// shared now that share codes are gone. Minted server-side by
  /// `trg_set_collection_slug` — never written from the client.
  final String slug;

  /// Whether strangers can open that URL. The share link is worth offering
  /// only when this is true; a private collection 404s for everyone else.
  final bool isPublic;
  final int cardCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory WantlistModel.fromRow(Map<String, dynamic> row) {
    // `collection_cards(count)` embeds as `[{count: n}]`.
    var cardCount = 0;
    final counts = row['collection_cards'];
    if (counts is List && counts.isNotEmpty) {
      final first = counts.first;
      if (first is Map) cardCount = (first['count'] as num?)?.toInt() ?? 0;
    }

    return WantlistModel(
      id: row['id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      slug: row['slug'] as String? ?? '',
      isPublic: row['is_public'] as bool? ?? false,
      cardCount: cardCount,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
    );
  }
}
