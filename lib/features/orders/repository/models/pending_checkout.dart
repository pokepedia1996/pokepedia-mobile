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

  /// `carts.total_amount`. Preferred over summing the lines, which omits the
  /// gateway fee and any coupon.
  final int? totalAmount;

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
    totalAmount: (row['total_amount'] as num?)?.toInt(),
  );
}
