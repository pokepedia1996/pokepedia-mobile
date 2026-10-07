import '../../utils/package_payment.dart';

/// A checkout a buyer started against this seller's listings and hasn't paid
/// for yet — one row of web's "Menunggu pembayaran" tab.
///
/// Deliberately not an [OrderModel]: there is no order until the money
/// arrives. Web fakes one with a synthetic slug so its table can render it;
/// here it stays its own type, because everything the seller can *do* with an
/// order (ship it, print a label, cancel it) is unavailable until it exists.
class PendingCheckout {
  const PendingCheckout({
    required this.cartId,
    required this.externalId,
    required this.buyerUsername,
    required this.createdAt,
    required this.expiresAt,
    required this.items,
    required this.hasInvoice,
    this.invoiceUrl,
    this.totalAmount,
    this.sellerId,
    this.storeName,
    this.sellerUsername,
    this.sellerImageUrl,
  });

  /// Folds the RPC's per-line rows back into the checkout they belong to.
  factory PendingCheckout.fromRows(List<Map<String, dynamic>> rows) {
    final first = rows.first;
    return PendingCheckout(
      cartId: (first['cart_id'] as num).toInt(),
      externalId: first['external_id'] as String? ?? '',
      buyerUsername: first['buyer_username'] as String?,
      createdAt:
          DateTime.tryParse(first['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(
        first['expires_at'] as String? ?? '',
      )?.toLocal(),
      hasInvoice: first['has_invoice'] as bool? ?? false,
      items: rows.map(PendingCheckoutItem.fromRow).toList(),
    );
  }

  final int cartId;
  final String externalId;
  final String? buyerUsername;
  final DateTime createdAt;

  /// When the cart expires and the stock goes back on sale.
  final DateTime? expiresAt;
  final List<PendingCheckoutItem> items;

  /// Whether an invoice was raised. Without one the buyer never reached the
  /// payment page, so the cart will simply lapse.
  final bool hasInvoice;

  /// Where the buyer resumes paying. Null on the seller's view, which has no
  /// business reopening someone else's invoice.
  final String? invoiceUrl;

  /// What the buyer is billed: `carts.invoice_amount`, falling back to
  /// `total_amount` (see [cartChargedAmount]). Preferred over summing the
  /// lines, which omits the gateway fee and any coupon.
  final int? totalAmount;

  /// Who the cart is with. Carried on every snapshot line; a cart is locked to
  /// one seller, so the first line's is the cart's.
  final String? sellerId;

  /// Storefront name, `@username` and avatar — the three the card's header
  /// shows. Resolved by the repository rather than the snapshot, which stores
  /// only the id. Null until then, and for a seller-side view that has no
  /// business naming the buyer's counterparty.
  final String? storeName;
  final String? sellerUsername;
  final String? sellerImageUrl;

  /// The line under the store name, matching web's `resolveSellerDisplay`:
  /// the handle, hidden when it would just repeat the name above it.
  String? get sellerSecondaryName {
    final username = sellerUsername;
    if (username == null || username.isEmpty) return null;
    // Compared against what the header actually prints, not against
    // `storeName`: a seller with no storefront is already headlined by their
    // handle, and repeating it underneath reads as two different sellers.
    if (displayName.toLowerCase() == username.toLowerCase()) return null;
    return '@$username';
  }

  /// What the header calls the shop: its storefront name, falling back to the
  /// handle for a seller who never named one.
  String get displayName => (storeName != null && storeName!.isNotEmpty)
      ? storeName!
      : (sellerUsername != null && sellerUsername!.isNotEmpty)
      ? sellerUsername!
      : 'Penjual';

  PendingCheckout withSeller({
    String? storeName,
    String? sellerUsername,
    String? sellerImageUrl,
  }) => PendingCheckout(
    cartId: cartId,
    externalId: externalId,
    buyerUsername: buyerUsername,
    createdAt: createdAt,
    expiresAt: expiresAt,
    items: items,
    hasInvoice: hasInvoice,
    invoiceUrl: invoiceUrl,
    totalAmount: totalAmount,
    sellerId: sellerId,
    storeName: storeName ?? this.storeName,
    sellerUsername: sellerUsername ?? this.sellerUsername,
    sellerImageUrl: sellerImageUrl ?? this.sellerImageUrl,
  );

  /// Replaces the lines with enriched copies — the card art the snapshot has
  /// no room for.
  PendingCheckout withItems(List<PendingCheckoutItem> next) => PendingCheckout(
    cartId: cartId,
    externalId: externalId,
    buyerUsername: buyerUsername,
    createdAt: createdAt,
    expiresAt: expiresAt,
    items: next,
    hasInvoice: hasInvoice,
    invoiceUrl: invoiceUrl,
    totalAmount: totalAmount,
    sellerId: sellerId,
    storeName: storeName,
    sellerUsername: sellerUsername,
    sellerImageUrl: sellerImageUrl,
  );

  /// The seller's number, not the buyer's: the RPC has no order number to
  /// give, and web labels these `CART-<id>`.
  String get reference => 'CART-$cartId';

  int get total =>
      totalAmount ??
      items.fold(
        0,
        (sum, item) => sum + item.price * item.quantity + item.shippingCost,
      );

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  Duration? get remaining {
    final expiresAt = this.expiresAt;
    if (expiresAt == null) return null;
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

class PendingCheckoutItem {
  const PendingCheckoutItem({
    required this.cardId,
    required this.cardName,
    required this.expansionCode,
    required this.collectorNumber,
    required this.price,
    required this.quantity,
    this.imageUrl,
    this.condition,
    this.shippingCost = 0,
    this.courierService,
    this.askOrderId,
    this.sellerId,
  });

  factory PendingCheckoutItem.fromRow(Map<String, dynamic> row) {
    return PendingCheckoutItem(
      cardId: (row['card_id'] as num?)?.toInt() ?? 0,
      cardName: row['card_name'] as String? ?? 'Kartu',
      expansionCode: row['expansion_code'] as String? ?? '',
      collectorNumber: row['collector_number'] as String? ?? '',
      imageUrl: row['card_image_url'] as String?,
      condition: row['condition'] as String?,
      price: (row['price'] as num?)?.toInt() ?? 0,
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      shippingCost: (row['shipping_cost'] as num?)?.toInt() ?? 0,
      courierService: row['courier_service'] as String?,
    );
  }

  final int cardId;
  final String cardName;
  final String expansionCode;
  final String collectorNumber;
  final String? imageUrl;
  final String? condition;
  final int price;
  final int quantity;
  final int shippingCost;
  final String? courierService;

  /// `listings.id`. The snapshot stores this rather than the card, so it is
  /// the only way back to the artwork.
  final int? askOrderId;
  final String? sellerId;

  PendingCheckoutItem withCard({
    String? cardName,
    String? imageUrl,
    String? expansionCode,
    String? collectorNumber,
  }) => PendingCheckoutItem(
    cardId: cardId,
    cardName: cardName ?? this.cardName,
    expansionCode: expansionCode ?? this.expansionCode,
    collectorNumber: collectorNumber ?? this.collectorNumber,
    imageUrl: imageUrl ?? this.imageUrl,
    condition: condition,
    price: price,
    quantity: quantity,
    shippingCost: shippingCost,
    courierService: courierService,
    askOrderId: askOrderId,
    sellerId: sellerId,
  );
}

/// A checkout the *buyer* started and hasn't paid for.
///
/// Built from their own `carts` row rather than the seller RPC, because the
/// two sides see different things: a seller sees only the lines that are
/// theirs, a buyer sees the whole basket. `carts_select_own` makes the row
/// readable directly, and `cart_snapshot` carries the lines, so this needs
/// no server route.
///
/// Kept separate from [OrderModel] on purpose: until the webhook settles the
/// payment there is no order — nothing to ship, dispute or receive. Showing
/// it as one would promise more than exists.
PendingCheckout pendingCheckoutFromCart(Map<String, dynamic> row) {
  final snapshot = (row['cart_snapshot'] as List?) ?? const [];
  final items = <PendingCheckoutItem>[];

  for (final entry in snapshot) {
    if (entry is! Map<String, dynamic>) continue;
    items.add(
      PendingCheckoutItem(
        cardId: (entry['card_id'] as num?)?.toInt() ?? 0,
        cardName: entry['card_name'] as String? ?? 'Kartu',
        expansionCode: entry['expansion_code'] as String? ?? '',
        collectorNumber: entry['collector_number'] as String? ?? '',
        imageUrl: entry['card_image_url'] as String?,
        condition: entry['condition'] as String?,
        price: (entry['price'] as num?)?.toInt() ?? 0,
        quantity: (entry['quantity'] as num?)?.toInt() ?? 1,
        shippingCost: (entry['shipping_cost'] as num?)?.toInt() ?? 0,
        courierService: entry['courier_service'] as String?,
        askOrderId: (entry['ask_order_id'] as num?)?.toInt(),
        sellerId: entry['seller_id'] as String?,
      ),
    );
  }

  return PendingCheckout(
    // A buyer's cart has no numeric id in this shape; the external id is
    // what the payment and the status poll are both keyed by.
    cartId: (row['id'] as num?)?.toInt() ?? 0,
    externalId: row['external_id'] as String? ?? '',
    buyerUsername: null,
    createdAt:
        DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    expiresAt: DateTime.tryParse(row['expires_at'] as String? ?? '')?.toLocal(),
    hasInvoice: (row['invoice_url'] as String?)?.isNotEmpty ?? false,
    items: items,
    invoiceUrl: row['invoice_url'] as String?,
    totalAmount: cartChargedAmount(row),
    sellerId: items.isEmpty ? null : items.first.sellerId,
  );
}
