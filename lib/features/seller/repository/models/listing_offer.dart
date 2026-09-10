import '../../../../shared/models/card_condition.dart';

/// Who moved last, and who each history entry belongs to.
enum OfferActor {
  buyer('buyer', 'Pembeli'),
  seller('seller', 'Penjual');

  const OfferActor(this.code, this.label);

  final String code;
  final String label;

  static OfferActor from(String? raw) => OfferActor.values.firstWhere(
    (a) => a.code == raw,
    orElse: () => OfferActor.buyer,
  );
}

enum OfferStatus {
  pending('pending', 'Menunggu'),
  accepted('accepted', 'Diterima'),
  rejected('rejected', 'Ditolak'),
  withdrawn('withdrawn', 'Ditarik'),
  expired('expired', 'Kadaluwarsa');

  const OfferStatus(this.code, this.label);

  final String code;
  final String label;

  static OfferStatus from(String? raw) => OfferStatus.values.firstWhere(
    (s) => s.code == raw,
    orElse: () => OfferStatus.expired,
  );
}

/// Where an *accepted* offer got to. Null until it is accepted — an offer
/// nobody has said yes to has no payment to be in a state about.
enum OfferPaymentState {
  awaiting('awaiting', 'Menunggu Bayar'),
  paid('paid', 'Dibayar'),
  cancelled('cancelled', 'Dibatalkan'),
  expired('expired', 'Kadaluwarsa');

  const OfferPaymentState(this.code, this.label);

  final String code;
  final String label;
}

/// The four lists the seller's offer screen is split into.
enum OfferBucket {
  received('Masuk'),
  sent('Terkirim'),
  awaitingPayment('Menunggu Bayar'),
  completed('Selesai');

  const OfferBucket(this.label);

  final String label;
}

enum OfferAction {
  offer('offer', 'mengajukan penawaran'),
  counter('counter', 'menawar balik'),
  accept('accept', 'menerima'),
  reject('reject', 'menolak'),
  withdraw('withdraw', 'menarik penawaran');

  const OfferAction(this.code, this.label);

  final String code;
  final String label;

  static OfferAction from(String? raw) => OfferAction.values.firstWhere(
    (a) => a.code == raw,
    orElse: () => OfferAction.offer,
  );
}

/// One move in a negotiation.
class OfferHistoryEntry {
  const OfferHistoryEntry({
    required this.actor,
    required this.action,
    required this.at,
    this.price,
    this.message,
  });

  factory OfferHistoryEntry.fromJson(Map<String, dynamic> json) {
    return OfferHistoryEntry(
      actor: OfferActor.from(json['actor'] as String?),
      action: OfferAction.from(json['action'] as String?),
      at:
          DateTime.tryParse(json['at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      price: (json['price'] as num?)?.toInt(),
      message: json['message'] as String?,
    );
  }

  final OfferActor actor;
  final OfferAction action;
  final DateTime at;
  final int? price;
  final String? message;
}

/// A buyer's offer on one of the seller's listings.
///
/// Read straight from `listing_offers` rather than through web's
/// `/api/listing-offers/received`: that route reaches for the service client
/// only to join `profiles` and the buyer's address, and
/// `listing_offers_self_select` already lets a seller read their own rows.
/// The one thing it can fetch and this can't is the buyer's ship-to city:
/// `user_addresses_select_own` is own-rows-only, so the screen shows the
/// same "confirmed at checkout" line web falls back to when a buyer has no
/// primary address.
class ListingOffer {
  const ListingOffer({
    required this.slug,
    required this.listingSlug,
    required this.status,
    required this.quantity,
    required this.listingPrice,
    required this.currentPrice,
    required this.lastActor,
    required this.buyerCounterCount,
    required this.sellerCounterCount,
    required this.condition,
    required this.expiresAt,
    required this.createdAt,
    required this.cardName,
    required this.cardId,
    this.variantKey,
    this.message,
    this.history = const [],
    this.rejectionNote,
    this.respondedAt,
    this.seenAt,
    this.paymentState,
    this.buyerId,
    this.buyerUsername,
    this.buyerAvatarUrl,
    this.cardImageUrl,
    this.expansionCode,
    this.collectorNumber,
    this.variant,
  });

  factory ListingOffer.fromRow(Map<String, dynamic> row) {
    final card = row['cards'] as Map<String, dynamic>?;
    final listing = row['listings'] as Map<String, dynamic>?;
    final orderItem = row['order_items'] as Map<String, dynamic>?;

    final status = OfferStatus.from(row['status'] as String?);
    final expiresAt =
        DateTime.tryParse(row['expires_at'] as String? ?? '')?.toLocal() ??
        DateTime.now();

    return ListingOffer(
      slug: row['slug'] as String? ?? '',
      listingSlug: listing?['slug'] as String? ?? '',
      status: status,
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      listingPrice: (row['listing_price'] as num?)?.toInt() ?? 0,
      currentPrice: (row['current_price'] as num?)?.toInt() ?? 0,
      lastActor: OfferActor.from(row['last_actor'] as String?),
      buyerCounterCount: (row['buyer_counter_count'] as num?)?.toInt() ?? 0,
      sellerCounterCount: (row['seller_counter_count'] as num?)?.toInt() ?? 0,
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      variantKey: row['variant_key'] as String?,
      message: row['message'] as String?,
      history: [
        for (final entry in (row['history'] as List?) ?? const [])
          if (entry is Map<String, dynamic>) OfferHistoryEntry.fromJson(entry),
      ],
      rejectionNote: row['rejection_note'] as String?,
      expiresAt: expiresAt,
      respondedAt: DateTime.tryParse(
        row['responded_at'] as String? ?? '',
      )?.toLocal(),
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      seenAt: DateTime.tryParse(row['seen_at'] as String? ?? '')?.toLocal(),
      paymentState: _paymentState(
        status: status,
        hasOrderItem: row['order_item_id'] != null,
        orderItemStatus: orderItem?['status'] as String?,
        expiresAt: expiresAt,
      ),
      buyerId: row['buyer_id'] as String?,
      cardId: (card?['id'] as num?)?.toInt() ?? (row['card_id'] as num).toInt(),
      cardName: card?['name_id'] as String? ?? 'Kartu',
      cardImageUrl: card?['image_url'] as String?,
      expansionCode: card?['expansion_code'] as String?,
      collectorNumber: card?['collector_number'] as String?,
      variant: switch (card?['variant'] as String?) {
        null || 'normal' => null,
        final v => v,
      },
    );
  }

  final String slug;

  /// The listing this offer is against — `listings.slug`, which is what the
  /// per-listing screen is keyed by.
  final String listingSlug;
  final OfferStatus status;
  final int quantity;
  final int listingPrice;
  final int currentPrice;
  final OfferActor lastActor;
  final int buyerCounterCount;
  final int sellerCounterCount;
  final CardCondition condition;
  final String? variantKey;
  final String? message;
  final List<OfferHistoryEntry> history;
  final String? rejectionNote;
  final DateTime expiresAt;
  final DateTime? respondedAt;
  final DateTime createdAt;
  final DateTime? seenAt;
  final OfferPaymentState? paymentState;
  final String? buyerId;
  final String? buyerUsername;
  final String? buyerAvatarUrl;
  final int cardId;
  final String cardName;
  final String? cardImageUrl;
  final String? expansionCode;
  final String? collectorNumber;
  final String? variant;

  /// Web's `MAX_COUNTERS_PER_SIDE`. Past this the seller can only accept or
  /// reject, and the RPC refuses another counter anyway.
  static const maxCountersPerSide = 5;

  ListingOffer withBuyer({String? username, String? avatarUrl}) =>
      _copy(buyerUsername: username, buyerAvatarUrl: avatarUrl);

  ListingOffer markedSeen(DateTime at) => _copy(seenAt: at);

  /// The seller's move to make. Pending *and* the buyer spoke last — an offer
  /// waiting on the buyer is not the seller's turn, however open it looks.
  bool get needsSellerResponse =>
      status == OfferStatus.pending && lastActor == OfferActor.buyer;

  bool get waitingOnBuyer =>
      status == OfferStatus.pending && lastActor == OfferActor.seller;

  bool get canCounter => sellerCounterCount < maxCountersPerSide;

  bool get priceDropped => currentPrice < listingPrice;

  /// What the pill says. An accepted offer is described by where the money
  /// got to, because "Diterima" stops being the useful fact the moment it is.
  String get statusLabel => paymentState?.label ?? status.label;

  OfferBucket get bucket {
    if (status == OfferStatus.pending) {
      return lastActor == OfferActor.buyer
          ? OfferBucket.received
          : OfferBucket.sent;
    }
    if (status == OfferStatus.accepted) {
      return paymentState == OfferPaymentState.awaiting
          ? OfferBucket.awaitingPayment
          : OfferBucket.completed;
    }
    return OfferBucket.completed;
  }

  /// Counts toward the listing's badge: still live, still worth a look.
  bool get isActionable =>
      status == OfferStatus.pending ||
      (status == OfferStatus.accepted &&
          paymentState == OfferPaymentState.awaiting);

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  ListingOffer _copy({
    String? buyerUsername,
    String? buyerAvatarUrl,
    DateTime? seenAt,
  }) => ListingOffer(
    slug: slug,
    listingSlug: listingSlug,
    status: status,
    quantity: quantity,
    listingPrice: listingPrice,
    currentPrice: currentPrice,
    lastActor: lastActor,
    buyerCounterCount: buyerCounterCount,
    sellerCounterCount: sellerCounterCount,
    condition: condition,
    variantKey: variantKey,
    message: message,
    history: history,
    rejectionNote: rejectionNote,
    expiresAt: expiresAt,
    respondedAt: respondedAt,
    createdAt: createdAt,
    seenAt: seenAt ?? this.seenAt,
    paymentState: paymentState,
    buyerId: buyerId,
    buyerUsername: buyerUsername ?? this.buyerUsername,
    buyerAvatarUrl: buyerAvatarUrl ?? this.buyerAvatarUrl,
    cardId: cardId,
    cardName: cardName,
    cardImageUrl: cardImageUrl,
    expansionCode: expansionCode,
    collectorNumber: collectorNumber,
    variant: variant,
  );
}

/// Mirrors web's `derivePaymentState`.
OfferPaymentState? _paymentState({
  required OfferStatus status,
  required bool hasOrderItem,
  required String? orderItemStatus,
  required DateTime expiresAt,
}) {
  if (status != OfferStatus.accepted) return null;
  if (hasOrderItem) {
    return orderItemStatus == 'cancelled'
        ? OfferPaymentState.cancelled
        : OfferPaymentState.paid;
  }
  return expiresAt.isAfter(DateTime.now())
      ? OfferPaymentState.awaiting
      : OfferPaymentState.expired;
}

/// How many live offers sit on a listing, and how many are the seller's move.
class OfferCount {
  const OfferCount({required this.total, required this.needsResponse});

  final int total;
  final int needsResponse;
}

/// Per-listing badge counts, keyed by `listings.slug`.
///
/// Only actionable offers count. A rejected or long-settled offer on the
/// listing row would read as work outstanding when there is none.
Map<String, OfferCount> buildOfferCounts(Iterable<ListingOffer> offers) {
  final counts = <String, OfferCount>{};
  for (final offer in offers) {
    if (!offer.isActionable || offer.listingSlug.isEmpty) continue;
    final existing = counts[offer.listingSlug];
    counts[offer.listingSlug] = OfferCount(
      total: (existing?.total ?? 0) + 1,
      needsResponse:
          (existing?.needsResponse ?? 0) + (offer.needsSellerResponse ? 1 : 0),
    );
  }
  return counts;
}

/// Which offer the screen opens on: the one the seller has to answer, then
/// the live ones, then the rest — newest first inside each band.
ListingOffer? pickDefaultOffer(List<ListingOffer> offers) {
  if (offers.isEmpty) return null;
  final sorted = [...offers]
    ..sort((a, b) {
      final rank = _actionRank(a) - _actionRank(b);
      if (rank != 0) return rank;
      return b.createdAt.compareTo(a.createdAt);
    });
  return sorted.first;
}

int _actionRank(ListingOffer offer) {
  if (offer.needsSellerResponse) return 0;
  if (offer.status == OfferStatus.accepted) return 1;
  if (offer.status == OfferStatus.pending) return 2;
  return 3;
}
