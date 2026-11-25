import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';

/// Limits on a custom listing, the same as web's `custom-listing.ts` and the
/// checks `save_custom_listing` makes.
const customTitleMin = 5;
const customTitleMax = 40;
const customDescriptionMax = 1000;
const customMaxPhotos = 8;
const customMaxTags = 50;
const customPriceMax = 999999999;
const customMaxQuantity = 99;

/// Web's `customTitleError`: null when the title can be published.
String? customTitleError(String title) {
  final length = title.trim().runes.length;
  if (length < customTitleMin) return 'Judul minimal $customTitleMin karakter.';
  if (length > customTitleMax)
    return 'Judul maksimal $customTitleMax karakter.';
  return null;
}

/// `save_custom_listing`'s error codes in the seller's words, as web's
/// `mapSaveCustomListingError` puts them.
String customListingSaveError(String code) => switch (code) {
  'unauthorized' => 'Sesi habis. Login ulang.',
  'phone_not_verified' => 'Verifikasi nomor HP dulu.',
  'seller_profile_incomplete' => 'Lengkapi profil toko dulu.',
  'no_couriers' => 'Pilih kurir di pengaturan toko.',
  'invalid_title' => 'Judul harus $customTitleMin–$customTitleMax karakter.',
  'invalid_description' => 'Deskripsi maksimal $customDescriptionMax karakter.',
  'invalid_price' => 'Isi harga yang valid.',
  'invalid_quantity' || 'quantity_below_locked' => 'Stok tidak valid.',
  'photo_required' => 'Tambahkan minimal 1 foto.',
  'too_many_photos' => 'Maksimal $customMaxPhotos foto.',
  'invalid_photo' => 'URL foto tidak valid.',
  'too_many_drafts' =>
    'Draft custom sudah penuh (maks. 50). Hapus draft lama dulu.',
  'invalid_tag' || 'too_many_tags' => 'Kartu yang di-tag tidak valid.',
  'duplicate_tag' => 'Kartu dengan kondisi yang sama di-tag dua kali.',
  'trading_disabled' =>
    'Salah satu kartu yang di-tag sedang tidak bisa diperdagangkan.',
  'order_not_found' => 'Listing tidak ditemukan.',
  'order_not_editable' => 'Listing ini tidak bisa diedit lagi.',
  'order_locked_by_buyer' =>
    'Sudah ada pembeli yang sedang membayar listing ini.',
  'offers_pending' =>
    'Masih ada penawaran yang berjalan. Selesaikan atau tolak dulu '
        'sebelum mengedit.',
  'too_many_listings' =>
    'Listing custom aktif sudah penuh (maks. 200). Nonaktifkan yang lama '
        'dulu.',
  'invalid_args' => 'Data listing tidak valid.',
  _ => 'Gagal menyimpan listing.',
};

/// A catalog card tagged on a custom listing, as the form holds it.
class CustomFormTag {
  const CustomFormTag({
    required this.cardId,
    required this.name,
    required this.number,
    required this.expansionCode,
    required this.language,
    this.imageUrl,
    this.condition = CardCondition.nm,
    this.quantity = 1,
  });

  /// A card picked from the catalog: NM and the copies picked, as web's
  /// `tagFromStaged` starts it.
  factory CustomFormTag.fromCard(CardModel card, int quantity) => CustomFormTag(
    cardId: card.id,
    name: card.name,
    number: card.collectorNumber,
    expansionCode: card.expansionCode,
    language: card.language,
    imageUrl: card.imageUrl,
    quantity: quantity.clamp(1, customMaxQuantity),
  );

  /// An entry of `get_custom_listing`'s `tags`.
  factory CustomFormTag.fromJson(Map<String, dynamic> json) => CustomFormTag(
    cardId: (json['card_id'] as num?)?.toInt() ?? 0,
    name: json['card_name'] as String? ?? '',
    number: json['collector_number'] as String? ?? '',
    expansionCode: json['expansion_code'] as String? ?? '',
    language: CardLanguage.fromRaw(json['language'] as String?),
    imageUrl: json['image_url'] as String?,
    condition: CardConditionX.fromRaw(json['condition'] as String? ?? 'NM'),
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
  );

  final int cardId;
  final String name;
  final String number;
  final String expansionCode;
  final CardLanguage language;
  final String? imageUrl;
  final CardCondition condition;
  final int quantity;

  /// A tag is one card in one condition: the same card twice in one
  /// condition is one tag with more copies.
  bool sameAs(CustomFormTag other) =>
      other.cardId == cardId && other.condition == condition;

  CustomFormTag copyWith({CardCondition? condition, int? quantity}) =>
      CustomFormTag(
        cardId: cardId,
        name: name,
        number: number,
        expansionCode: expansionCode,
        language: language,
        imageUrl: imageUrl,
        condition: condition ?? this.condition,
        quantity: quantity ?? this.quantity,
      );

  Map<String, dynamic> toRpc() => {
    'card_id': cardId,
    'condition': condition.raw,
    'quantity': quantity,
  };
}

/// Web's `mergeTags`: [added] joined onto [existing], a card already there in
/// the same condition taking the extra copies (up to 99) rather than a
/// second row.
List<CustomFormTag> mergeCustomTags(
  List<CustomFormTag> existing,
  List<CustomFormTag> added,
) {
  final merged = [...existing];
  for (final tag in added) {
    final match = merged.indexWhere(tag.sameAs);
    if (match < 0) {
      merged.add(tag);
    } else {
      final total = merged[match].quantity + tag.quantity;
      merged[match] = merged[match].copyWith(
        quantity: total.clamp(1, customMaxQuantity),
      );
    }
  }
  return merged;
}

/// Everything the custom listing form edits.
class CustomListingFormValue {
  const CustomListingFormValue({
    this.slug,
    this.title = '',
    this.description = '',
    this.price,
    this.quantity = 1,
    this.photoUrls = const [],
    this.tags = const [],
    this.acceptsOffers = false,
    this.autoRelist = false,
    this.isDraft = true,
    this.qtyLocked = 0,
  });

  /// A blank listing, with the seller's Preferensi for the two toggles.
  factory CustomListingFormValue.blank({
    required bool acceptsOffers,
    required bool autoRelist,
  }) => CustomListingFormValue(
    acceptsOffers: acceptsOffers,
    autoRelist: autoRelist,
  );

  /// `get_custom_listing` as its owner gets it. The photo URLs are kept
  /// as stored — `save_custom_listing` only accepts the seller's own
  /// Storage URLs, not the proxied ones a screen draws.
  factory CustomListingFormValue.fromDetail(Map<String, dynamic> json) =>
      CustomListingFormValue(
        slug: json['slug'] as String?,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: (json['price'] as num?)?.toInt(),
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        photoUrls: ((json['photo_urls'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        tags: [
          for (final tag in (json['tags'] as List?) ?? const [])
            if (tag is Map<String, dynamic>) CustomFormTag.fromJson(tag),
        ],
        acceptsOffers: json['accepts_offers'] as bool? ?? false,
        autoRelist: json['auto_relist'] as bool? ?? false,
        isDraft: (json['status'] as String?) == 'draft',
        qtyLocked: (json['qty_locked'] as num?)?.toInt() ?? 0,
      );

  /// Null until the first save.
  final String? slug;
  final String title;
  final String description;
  final int? price;
  final int quantity;
  final List<String> photoUrls;
  final List<CustomFormTag> tags;
  final bool acceptsOffers;
  final bool autoRelist;

  /// Not yet published. A published listing has no draft to fall back to.
  final bool isDraft;

  /// Copies in buyers' checkouts: stock can't go below them.
  final int qtyLocked;

  /// Web's `publishBlocker`: why it can't be published yet, or null.
  String? get publishBlocker {
    if (photoUrls.isEmpty) return 'Tambahkan minimal 1 foto.';
    final titleError = customTitleError(title);
    if (titleError != null) return titleError;
    if (price == null) return 'Isi harga dulu.';
    return null;
  }

  CustomListingFormValue copyWith({
    String? slug,
    String? title,
    String? description,
    int? Function()? price,
    int? quantity,
    List<String>? photoUrls,
    List<CustomFormTag>? tags,
    bool? acceptsOffers,
    bool? autoRelist,
  }) => CustomListingFormValue(
    slug: slug ?? this.slug,
    title: title ?? this.title,
    description: description ?? this.description,
    price: price == null ? this.price : price(),
    quantity: quantity ?? this.quantity,
    photoUrls: photoUrls ?? this.photoUrls,
    tags: tags ?? this.tags,
    acceptsOffers: acceptsOffers ?? this.acceptsOffers,
    autoRelist: autoRelist ?? this.autoRelist,
    isDraft: isDraft,
    qtyLocked: qtyLocked,
  );

  /// `save_custom_listing`'s parameters, as web's `callSaveCustomListing`
  /// sends them.
  Map<String, dynamic> toRpcParams({required bool publish}) => {
    'p_slug': slug,
    'p_title': title,
    'p_description': description,
    'p_price': price,
    'p_quantity': quantity,
    'p_photo_urls': photoUrls,
    'p_tags': [for (final tag in tags) tag.toRpc()],
    'p_accepts_offers': acceptsOffers,
    'p_auto_relist': autoRelist,
    'p_publish': publish,
  };
}

/// One unpublished custom listing, for the Draft tab.
class CustomDraftSummary {
  const CustomDraftSummary({
    required this.slug,
    this.title,
    this.price,
    this.quantity = 1,
    this.coverUrl,
  });

  factory CustomDraftSummary.fromRow(Map<String, dynamic> row) =>
      CustomDraftSummary(
        slug: row['slug'] as String? ?? '',
        title: row['title'] as String?,
        price: (row['price'] as num?)?.toInt(),
        quantity: (row['quantity'] as num?)?.toInt() ?? 1,
        coverUrl: ((row['photo_urls'] as List?) ?? const [])
            .whereType<String>()
            .firstOrNull,
      );

  final String slug;
  final String? title;
  final int? price;
  final int quantity;
  final String? coverUrl;
}
