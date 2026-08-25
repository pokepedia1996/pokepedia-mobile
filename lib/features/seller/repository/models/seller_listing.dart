import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';

/// Which slice of the seller's listings is on screen.
///
/// Archiving is a timestamp (`archived_at`), not a status — an archived
/// listing keeps whatever status it had — so the active bucket has to
/// exclude it explicitly rather than just filtering on `status`.
enum SellerListingBucket {
  active('Aktif', 'open'),
  sold('Terjual', 'matched'),
  expired('Kedaluwarsa', 'expired'),
  archived('Arsip', null);

  const SellerListingBucket(this.label, this.status);

  final String label;

  /// The `listings.status` this bucket reads, or null when the bucket is
  /// defined by `archived_at` instead.
  final String? status;

  bool get isArchived => this == SellerListingBucket.archived;
}

/// One of the seller's own listings, with the fields their product list acts
/// on. Distinct from [CardModel]-carrying `ListingModel` used on the buyer
/// side: this is the row as its owner sees it, including the counters and
/// toggles a buyer never gets.
class SellerListing {
  const SellerListing({
    required this.id,
    required this.slug,
    required this.card,
    required this.price,
    required this.condition,
    required this.quantity,
    required this.qtyLocked,
    required this.status,
    required this.acceptsOffers,
    required this.autoRelist,
    required this.viewCount,
    required this.createdAt,
    this.archivedAt,
    this.expiresAt,
  });

  final int id;

  /// `listings.slug` is a uuid, and it's what every seller RPC takes.
  final String slug;

  final CardModel card;
  final int price;
  final CardCondition condition;
  final int quantity;
  final int qtyLocked;
  final String status;
  final bool acceptsOffers;
  final bool autoRelist;
  final int viewCount;
  final DateTime? createdAt;

  /// Set means archived, whatever [status] says.
  final DateTime? archivedAt;
  final DateTime? expiresAt;

  bool get isArchived => archivedAt != null;

  /// What a buyer could still take.
  int get available => quantity - qtyLocked;

  bool get isOutOfStock => available <= 0;

  factory SellerListing.fromRow(Map<String, dynamic> row) {
    return SellerListing(
      id: row['id'] as int,
      slug: row['slug'] as String? ?? '',
      card: CardModel.fromRow(row['cards'] as Map<String, dynamic>),
      price: (row['price'] as num?)?.toInt() ?? 0,
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      quantity: (row['quantity'] as num?)?.toInt() ?? 0,
      qtyLocked: (row['qty_locked'] as num?)?.toInt() ?? 0,
      status: row['status'] as String? ?? 'open',
      acceptsOffers: row['accepts_offers'] as bool? ?? false,
      autoRelist: row['auto_relist'] as bool? ?? false,
      viewCount: (row['view_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      archivedAt: DateTime.tryParse(row['archived_at'] as String? ?? ''),
      expiresAt: DateTime.tryParse(row['expires_at'] as String? ?? ''),
    );
  }
}
