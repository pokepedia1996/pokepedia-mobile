import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';

/// An accepted bid proposal waiting to be paid: a `carts` row of
/// `kind = 'bid'` that `accept_bid_proposal` opened with no invoice yet.
///
/// Ports the `PendingCheckout` deals web's checkout page takes through
/// `?d=` (`app/cart/checkout/page.tsx`): the price and quantity are already
/// fixed by the deal, so the buyer only picks the address, the courier and
/// how to pay, and `/api/cart/checkout` folds it in through
/// `selectedDealExternalIds`.
class CheckoutDeal {
  const CheckoutDeal({
    required this.externalId,
    required this.sellerId,
    required this.lines,
    this.expiresAt,
    this.storeName,
    this.storeLogoUrl,
  });

  /// Reads one `carts` row. Null when the snapshot names no seller, which
  /// leaves nothing to quote shipping from.
  static CheckoutDeal? fromCartRow(Map<String, dynamic> row) {
    final externalId = row['external_id'];
    if (externalId is! String || externalId.isEmpty) return null;

    final snapshot = row['cart_snapshot'];
    final lines = <CheckoutDealLine>[
      if (snapshot is List)
        for (final entry in snapshot.whereType<Map<String, dynamic>>())
          CheckoutDealLine.fromSnapshot(entry),
    ];
    final sellerId = lines
        .map((line) => line.sellerId)
        .whereType<String>()
        .firstOrNull;
    if (sellerId == null) return null;

    return CheckoutDeal(
      externalId: externalId,
      sellerId: sellerId,
      lines: lines,
      expiresAt: DateTime.tryParse(
        row['expires_at'] as String? ?? '',
      )?.toLocal(),
    );
  }

  /// `INV-BID-…`, what `selectedDealExternalIds` names.
  final String externalId;

  /// A deal is one proposal, so one seller — the snapshot's first named one.
  final String sellerId;
  final List<CheckoutDealLine> lines;

  /// 24 hours after the accept; past it the stock goes back on sale.
  final DateTime? expiresAt;

  /// From `get_store_identities`, since the snapshot carries only the id.
  final String? storeName;
  final String? storeLogoUrl;

  /// `PendingCheckout.itemsSubtotal`: price × quantity over the snapshot,
  /// the same sum `dealValueBySeller` in the checkout route declares.
  int get subtotal => lines.fold(0, (sum, line) => sum + line.subtotal);

  int get quantity => lines.fold(0, (sum, line) => sum + line.quantity);

  CheckoutDeal withStore({String? storeName, String? storeLogoUrl}) =>
      CheckoutDeal(
        externalId: externalId,
        sellerId: sellerId,
        lines: lines,
        expiresAt: expiresAt,
        storeName: storeName ?? this.storeName,
        storeLogoUrl: storeLogoUrl ?? this.storeLogoUrl,
      );
}

/// One snapshot line of a deal, as `accept_bid_proposal` writes it.
class CheckoutDealLine {
  const CheckoutDealLine({
    required this.cardName,
    required this.price,
    required this.quantity,
    this.cardId,
    this.imageUrl,
    this.condition,
    this.sellerId,
  });

  factory CheckoutDealLine.fromSnapshot(Map<String, dynamic> entry) {
    final condition = entry['condition'];
    return CheckoutDealLine(
      cardId: (entry['card_id'] as num?)?.toInt(),
      cardName: entry['card_name'] as String? ?? 'Kartu',
      imageUrl: (entry['card_image'] ?? entry['card_image_url']) as String?,
      condition: condition is String ? CardConditionX.fromRaw(condition) : null,
      price: (entry['price'] as num?)?.toInt() ?? 0,
      quantity: (entry['quantity'] as num?)?.toInt() ?? 0,
      sellerId: entry['seller_id'] as String?,
    );
  }

  final int? cardId;
  final String cardName;
  final String? imageUrl;
  final CardCondition? condition;
  final int price;
  final int quantity;
  final String? sellerId;

  int get subtotal => price * quantity;

  /// A sealed product carries no grade worth showing — `isSealedCardId`.
  bool get isSealed => isSealedCardId(cardId);
}
