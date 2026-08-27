import '../../../../core/utils/image_url.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';

/// Which slice of the seller's listings is on screen — the same three the
/// web uses (`features/seller/utils/listing-buckets.ts`, mirrored in
/// `get_seller_listings_page`).
///
/// Two rules that aren't obvious from `status` alone:
/// archiving is a timestamp (`archived_at`), not a status, so an archived
/// listing keeps whatever status it had and every other bucket has to
/// exclude it; and an *open* listing past its `expires_at` counts as
/// inactive, not active — it isn't buyable, whatever the column says.
enum SellerListingBucket {
  active('Aktif', 'Kelola listing yang sedang aktif di market dan orderbook.'),
  inactive(
    'Inaktif',
    'Listing yang terjual, kedaluwarsa, atau kehabisan stok.',
  ),
  archived(
    'Arsip',
    'Listing yang kamu arsipkan. Bisa dikembalikan kapan saja.',
  ),
  draft('Draft', 'Draft yang belum dipasang ke market.'),
  preferences('Preferensi', 'Pengaturan bawaan untuk listing barumu.');

  const SellerListingBucket(this.label, this.description);

  final String label;

  /// The line web prints under "Kelola Listing" for this tab.
  final String description;

  bool get isArchived => this == SellerListingBucket.archived;

  /// The three that read `listings`. Draft reads `listing_drafts` and
  /// Preferensi reads no list at all.
  bool get isListingBucket =>
      this == SellerListingBucket.active ||
      this == SellerListingBucket.inactive ||
      this == SellerListingBucket.archived;
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
    this.photoUrls = const [],
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

  /// The seller's own photos of this copy. Web badges the thumbnail with
  /// how many there are, because a listing over Rp100rb needs at least one.
  final List<String> photoUrls;

  bool get isArchived => archivedAt != null;

  /// What the whole row is worth at the asking price — web's value column.
  int get totalValue => price * quantity;

  /// What a buyer could still take.
  int get available => quantity - qtyLocked;

  bool get isOutOfStock => available <= 0;

  /// Open, but past its expiry — web counts this as inactive.
  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  /// The bucket this row belongs to, by the same predicates the server uses.
  SellerListingBucket get bucket {
    if (isArchived) return SellerListingBucket.archived;
    if (status == 'open' && !isExpired) return SellerListingBucket.active;
    return SellerListingBucket.inactive;
  }

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
      photoUrls: ((row['photo_urls'] as List?) ?? const [])
          .map((url) => proxyImageUrl(url as String?))
          .whereType<String>()
          .toList(),
    );
  }
}

/// A listing the seller started but hasn't posted — `listing_drafts`, which
/// is own-row CRUD so the app reads and deletes it directly.
class SellerDraft {
  const SellerDraft({
    required this.id,
    required this.card,
    required this.condition,
    required this.quantity,
    required this.photoCount,
    this.price,
    this.updatedAt,
  });

  factory SellerDraft.fromRow(Map<String, dynamic> row) {
    return SellerDraft(
      id: (row['id'] as num).toInt(),
      card: CardModel.fromRow(row['cards'] as Map<String, dynamic>),
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      photoCount: ((row['photo_urls'] as List?) ?? const []).length,
      price: (row['price'] as num?)?.toInt(),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
    );
  }

  final int id;
  final CardModel card;
  final CardCondition condition;
  final int quantity;
  final int photoCount;

  /// Nullable in the table: a draft can exist before a price is decided.
  final int? price;
  final DateTime? updatedAt;
}

/// Web's Preferensi tab — the defaults stamped onto a seller's new listings.
class ListingDefaults {
  const ListingDefaults({this.autoRelist = false, this.acceptsOffers = false});

  final bool autoRelist;
  final bool acceptsOffers;

  ListingDefaults copyWith({bool? autoRelist, bool? acceptsOffers}) =>
      ListingDefaults(
        autoRelist: autoRelist ?? this.autoRelist,
        acceptsOffers: acceptsOffers ?? this.acceptsOffers,
      );
}

/// The columns web's product tables order by (`SellerListingSortCol`).
enum ListingSortCol {
  name,
  expansion,
  number,
  condition,
  price,
  quantity,
  views,
}

/// Which column the table is ordered by, and which way.
class ListingSort {
  const ListingSort(this.col, {this.ascending = false});

  final ListingSortCol col;
  final bool ascending;

  /// Tapping the active column flips it; tapping another moves to it,
  /// descending, which is how web's `toggleSort` behaves.
  ListingSort toggled(ListingSortCol next) =>
      col == next ? ListingSort(col, ascending: !ascending) : ListingSort(next);

  /// Applied client-side: the app already holds the seller's whole page of
  /// listings, and the RPC that sorts server-side isn't deployed.
  List<SellerListing> apply(List<SellerListing> listings) {
    int compare(SellerListing a, SellerListing b) => switch (col) {
      ListingSortCol.name => a.card.name.toLowerCase().compareTo(
        b.card.name.toLowerCase(),
      ),
      ListingSortCol.expansion => a.card.expansionCode.compareTo(
        b.card.expansionCode,
      ),
      // Collector numbers are "079/101", not integers, so they sort as text
      // — padded, so #9 doesn't land after #10.
      ListingSortCol.number => _padded(
        a.card.collectorNumber,
      ).compareTo(_padded(b.card.collectorNumber)),
      // Enum declaration order is the grading order, best first.
      ListingSortCol.condition => a.condition.index.compareTo(
        b.condition.index,
      ),
      ListingSortCol.price => a.price.compareTo(b.price),
      ListingSortCol.quantity => a.quantity.compareTo(b.quantity),
      ListingSortCol.views => a.viewCount.compareTo(b.viewCount),
    };

    final sorted = [...listings]..sort(compare);
    return ascending ? sorted : sorted.reversed.toList();
  }

  static String _padded(String value) =>
      value.replaceAllMapped(RegExp(r'\d+'), (m) => m[0]!.padLeft(6, '0'));
}
