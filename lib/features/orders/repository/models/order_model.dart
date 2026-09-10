import '../../../../shared/models/card_condition.dart';
import '../../../../shared/utils/postgrest_embed.dart';
import '../../../../shared/models/card_model.dart';
import 'seller_order.dart';
import 'shipment_destination.dart';

/// `orders.status` check constraint — the shipment-level status shown on
/// the buyer's order list.
enum OrderStatus {
  awaitingShipment,
  shipped,
  received,
  completed,
  cancelled,
  issue,
}

extension OrderStatusX on OrderStatus {
  static OrderStatus fromRaw(String? raw) => switch (raw) {
    'shipped' => OrderStatus.shipped,
    'received' => OrderStatus.received,
    'completed' => OrderStatus.completed,
    'cancelled' => OrderStatus.cancelled,
    'issue' => OrderStatus.issue,
    _ => OrderStatus.awaitingShipment,
  };

  String get raw {
    switch (this) {
      case OrderStatus.awaitingShipment:
        return 'awaiting_shipment';
      case OrderStatus.shipped:
        return 'shipped';
      case OrderStatus.received:
        return 'received';
      case OrderStatus.completed:
        return 'completed';
      case OrderStatus.cancelled:
        return 'cancelled';
      case OrderStatus.issue:
        return 'issue';
    }
  }

  String get label {
    switch (this) {
      case OrderStatus.awaitingShipment:
        return 'Menunggu Dikirim';
      case OrderStatus.shipped:
        return 'Dikirim';
      case OrderStatus.received:
        return 'Diterima';
      case OrderStatus.completed:
        return 'Selesai';
      case OrderStatus.cancelled:
        return 'Dibatalkan';
      case OrderStatus.issue:
        return 'Bermasalah';
    }
  }
}

/// `order_items.status` check constraint — the per-line-item lifecycle
/// (escrow acceptance -> payment hold -> release).
enum OrderItemStatus {
  pendingAcceptance,
  accepted,
  inEscrow,
  completed,
  cancelled,
  rejected,
  expired,
}

extension OrderItemStatusX on OrderItemStatus {
  static OrderItemStatus fromRaw(String? raw) => switch (raw) {
    'accepted' => OrderItemStatus.accepted,
    'in_escrow' => OrderItemStatus.inEscrow,
    'completed' => OrderItemStatus.completed,
    'cancelled' => OrderItemStatus.cancelled,
    'rejected' => OrderItemStatus.rejected,
    'expired' => OrderItemStatus.expired,
    _ => OrderItemStatus.pendingAcceptance,
  };

  String get label {
    switch (this) {
      case OrderItemStatus.pendingAcceptance:
        return 'Menunggu Konfirmasi Penjual';
      case OrderItemStatus.accepted:
        return 'Dikonfirmasi Penjual';
      case OrderItemStatus.inEscrow:
        return 'Dana Ditahan (Escrow)';
      case OrderItemStatus.completed:
        return 'Selesai';
      case OrderItemStatus.cancelled:
        return 'Dibatalkan';
      case OrderItemStatus.rejected:
        return 'Ditolak';
      case OrderItemStatus.expired:
        return 'Kedaluwarsa';
    }
  }
}

class OrderItemModel {
  /// One `order_items` row with its embedded card and settlement.
  factory OrderItemModel.fromRow(Map<String, dynamic> row) {
    final settlement = embeddedRow(row['settlements']);
    final card = embeddedRow(row['cards']);

    return OrderItemModel(
      id: (row['id'] as num?)?.toInt(),
      slug: row['slug'] as String? ?? '',
      orderNumber: row['order_number'] as String? ?? '',
      // A card row is always joined; the placeholder keeps a row with a
      // deleted card from taking the whole list down.
      card: card != null
          ? CardModel.fromRow(card)
          : CardModel(
              id: (row['card_id'] as num?)?.toInt() ?? 0,
              category: CardCategory.pokemon,
              nameId: 'Kartu tidak ditemukan',
              expansionCode: '',
              packSlug: '',
              collectorNumber: '',
              rarity: null,
            ),
      // Condition lives on the settlement: the listing it was bought from
      // may since have closed, and a closed listing isn't readable by the
      // buyer.
      condition: CardConditionX.fromRaw(
        settlement?['condition'] as String? ?? 'NM',
      ),
      matchedQuantity: (row['matched_quantity'] as num?)?.toInt() ?? 1,
      matchPrice: (row['match_price'] as num?)?.toInt() ?? 0,
      status: OrderItemStatusX.fromRaw(row['status'] as String?),
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      shippingCost: (settlement?['shipping_cost'] as num?)?.toInt() ?? 0,
      settlementStatus: settlement?['status'] as String?,
      paidAt: DateTime.tryParse(
        settlement?['paid_at'] as String? ?? '',
      )?.toLocal(),
      releasedAt: DateTime.tryParse(
        settlement?['released_at'] as String? ?? '',
      )?.toLocal(),
      paymentDeadline: DateTime.tryParse(
        settlement?['payment_deadline'] as String? ?? '',
      )?.toLocal(),
      cancelStatus: settlement?['cancel_status'] as String?,
      cancelReason: settlement?['cancel_reason'] as String?,
      invoiceUrl: embeddedRow(settlement?['carts'])?['invoice_url'] as String?,
      statusRaw: row['status'] as String?,
      dispute: _openDispute(row['disputes']),
    );
  }

  const OrderItemModel({
    this.id,
    required this.slug,
    required this.orderNumber,
    required this.card,
    required this.condition,
    required this.matchedQuantity,
    required this.matchPrice,
    required this.status,
    required this.createdAt,
    this.shippingCost = 0,
    this.settlementStatus,
    this.paidAt,
    this.releasedAt,
    this.paymentDeadline,
    this.cancelStatus,
    this.cancelReason,
    this.invoiceUrl,
    this.statusRaw,
    this.dispute,
  });

  /// `order_items.id` — what `confirm_receipt` takes, unlike everything
  /// else here which is keyed by slug.
  final int? id;

  final String slug;
  final String orderNumber;
  final CardModel card;
  final CardCondition condition;
  final int matchedQuantity;
  final int matchPrice;
  final OrderItemStatus status;
  final DateTime createdAt;

  /// `settlements.shipping_cost` — what the buyer paid to have it sent.
  final int shippingCost;

  /// `settlements.status` and `paid_at`. Payment is recorded by the
  /// timestamp rather than the status, which tracks the escrow's lifecycle.
  final String? settlementStatus;
  final DateTime? paidAt;

  /// `settlements.released_at` — when escrow paid out, which is what web
  /// dates "Pesanan selesai" from.
  final DateTime? releasedAt;

  /// `settlements.payment_deadline` — when an unpaid checkout expires.
  final DateTime? paymentDeadline;

  /// `settlements.cancel_status`; `pending_seller` is the buyer waiting on
  /// this seller to approve or refuse a cancellation.
  final String? cancelStatus;
  final String? cancelReason;

  /// `carts.invoice_url` — only selected by the detail query, and only
  /// present while the checkout is still open.
  final String? invoiceUrl;

  /// The raw `order_items.status`, kept alongside the parsed [status] because
  /// the seller buckets test it against string sets ported from web.
  final String? statusRaw;

  /// The open dispute on this item, if there is one.
  final ({String? slug, String? status})? dispute;

  int get subtotal => matchPrice * matchedQuantity;
}

/// The first dispute that still needs somebody to act. A settled one is
/// history, and treating it as live would strand the order in Komplain.
({String? slug, String? status})? _openDispute(Object? raw) {
  for (final row in embeddedRows(raw)) {
    final status = row['current_status'] as String?;
    if (status != null && activeDisputeStatuses.contains(status)) {
      return (slug: row['slug'] as String?, status: status);
    }
  }
  return null;
}

/// The Pesanan filter strip, matching web's `ORDER_TAB_KEYS`.
enum OrderTab {
  all,
  unpaid,
  processing,
  shipped,
  completed,
  cancelled,
  dispute,
}

extension OrderTabX on OrderTab {
  String get label => switch (this) {
    OrderTab.all => 'Semua',
    OrderTab.unpaid => 'Belum Bayar',
    OrderTab.processing => 'Diproses',
    OrderTab.shipped => 'Dikirim',
    OrderTab.completed => 'Selesai',
    OrderTab.cancelled => 'Dibatalkan',
    OrderTab.dispute => 'Komplain',
  };

  /// Ports `ORDER_EMPTY_COPY` — what each tab says when it has nothing to
  /// show. A single "Tidak ada pesanan di tab ini" told the buyer nothing
  /// about which shelf they were looking at.
  String get emptyHeadline => switch (this) {
    OrderTab.all => 'Belum ada pesanan',
    OrderTab.unpaid => 'Tidak ada pesanan menunggu pembayaran',
    OrderTab.processing => 'Tidak ada pesanan diproses',
    OrderTab.shipped => 'Tidak ada paket dikirim',
    OrderTab.completed => 'Belum ada pesanan selesai',
    OrderTab.cancelled => 'Tidak ada riwayat pembatalan',
    OrderTab.dispute => 'Tidak ada komplain aktif',
  };

  /// Web marks these two with a coloured dot when they aren't empty: one
  /// costs the buyer their order, the other their money.
  bool get isUrgent => this == OrderTab.unpaid || this == OrderTab.dispute;
}

/// A buyer order, mirroring `public.orders` joined with its
/// `public.order_items` in
/// `supabase/migrations/00000000000000_baseline.sql`.
class OrderModel {
  /// One `orders` row with its embedded items and shipment. [storeName] is
  /// resolved separately — `seller_profiles` is self-select only.
  factory OrderModel.fromRow(
    Map<String, dynamic> row, {
    required String storeName,
  }) {
    final shipment = embeddedRow(row['shipments']);

    return OrderModel(
      slug: row['slug'] as String? ?? '',
      orderNumber: row['order_number'] as String? ?? '',
      storeName: storeName,
      sellerId: row['seller_id'] as String?,
      status: OrderStatusX.fromRaw(row['status'] as String?),
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      items: embeddedRows(
        row['order_items'],
      ).map(OrderItemModel.fromRow).toList(),
      shipmentSlug: shipment?['slug'] as String?,
      trackingNumber: shipment?['tracking_number'] as String?,
      courier: shipment?['courier'] as String?,
      shipmentStatus: shipment?['status'] as String?,
      shipmentDeadline: DateTime.tryParse(
        shipment?['shipment_deadline'] as String? ?? '',
      )?.toLocal(),
      biteshipOrderId: shipment?['biteship_order_id'] as String?,
      biteshipBookError: shipment?['biteship_book_error'] as String?,
      originCollectionMethod: shipment?['origin_collection_method'] as String?,
      statusHistory: _statusHistory(shipment?['status_history']),
      // Declared, passed through `withSeller` and read by the history card
      // and the not-received window — but never parsed, so both silently saw
      // null on every order.
      shippedAt: DateTime.tryParse(
        shipment?['shipped_at'] as String? ?? '',
      )?.toLocal(),
      deliveredAt: DateTime.tryParse(
        shipment?['delivered_at'] as String? ?? '',
      )?.toLocal(),
      // Only the detail query selects these, so a list row leaves it null
      // rather than carrying an empty address.
      destination: shipment == null || !shipment.containsKey('destination_city')
          ? null
          : ShipmentDestination.fromRow(shipment),
    );
  }

  const OrderModel({
    required this.slug,
    required this.orderNumber,
    required this.storeName,
    required this.status,
    this.sellerId,
    required this.createdAt,
    required this.items,
    this.trackingNumber,
    this.courier,
    this.destination,
    this.shipmentSlug,
    this.shipmentStatus,
    this.shipmentDeadline,
    this.biteshipOrderId,
    this.biteshipBookError,
    this.originCollectionMethod,
    this.statusHistory,
    this.shippedAt,
    this.deliveredAt,
    this.sellerUsername,
    this.sellerAvatarUrl,
    this.sellerLogoUrl,
    this.sellerSlug,
  });

  final String slug;
  final String orderNumber;
  final String storeName;

  /// `orders.seller_id` — who to open a chat with.
  final String? sellerId;

  final OrderStatus status;
  final DateTime createdAt;
  final List<OrderItemModel> items;
  final String? trackingNumber;
  final String? courier;

  /// Where the parcel is going. Null on a list row, which doesn't fetch it,
  /// and before a shipment exists at all.
  final ShipmentDestination? destination;

  /// `shipments.slug`, the id the shipment routes take. Only the seller's
  /// query selects it; a buyer has nothing to dispatch.
  final String? shipmentSlug;

  /// `shipments.status` — distinct from [status] (`orders.status`), and what
  /// the seller buckets actually test.
  final String? shipmentStatus;

  /// When the seller has to have handed the package over.
  final DateTime? shipmentDeadline;

  /// Set once Biteship has the booking. Its absence next to a
  /// [biteshipBookError] means the booking never took.
  final String? biteshipOrderId;
  final String? biteshipBookError;

  /// `pickup` or `manual` — null while the seller still has to choose.
  final String? originCollectionMethod;

  /// `shipments.status_history`, the courier's own trail.
  final List<ShipmentStatusEntry>? statusHistory;

  /// Already selected by the orders query; the detail page's history needs
  /// them to date each step rather than only naming it.
  final DateTime? shippedAt;
  final DateTime? deliveredAt;

  /// When the money landed. Payment is recorded by `settlements.paid_at`,
  /// not by a status.
  DateTime? get paidAt => items.isEmpty ? null : items.first.paidAt;

  DateTime? get releasedAt => items.isEmpty ? null : items.first.releasedAt;

  /// What the buyer paid for the cards alone.
  int get itemsSubtotal => items.fold(0, (sum, item) => sum + item.subtotal);

  /// What they paid to have it sent.
  int get shippingTotal =>
      items.fold(0, (sum, item) => sum + item.shippingCost);

  /// The counterparty's identity, resolved separately: `seller_profiles` is
  /// self-select-only, so a store name and logo come from
  /// `get_store_identities` and the username and avatar from `profiles`.
  final String? sellerUsername;
  final String? sellerAvatarUrl;
  final String? sellerLogoUrl;
  final String? sellerSlug;

  /// Ports `resolveSellerDisplay`: a store name wins, the username is the
  /// fallback, and `@username` rides underneath only when the store chose a
  /// different name.
  String? get sellerSecondaryName {
    final username = sellerUsername;
    if (username == null || username.isEmpty) return null;
    return storeName.trim() == username ? null : '@$username';
  }

  /// The storefront handle to open for this seller, or null when there is
  /// nothing to open.
  ///
  /// `resolveSellerDisplay` falls back to the username when a seller has no
  /// `store_slug`: they still have a page at `/market/<username>`. Mobile
  /// only ever looked at the slug, so every seller without a storefront row
  /// drew a chevron that led nowhere. Guarded by web's `isSafeHandle`, since
  /// the handle goes straight into a route.
  static final _safeHandle = RegExp(r'^[\w.\-]{1,50}$');

  String? get sellerHandle {
    final slug = sellerSlug;
    if (slug != null && slug.isNotEmpty) return slug;
    final username = sellerUsername;
    if (username != null && _safeHandle.hasMatch(username)) return username;
    return null;
  }

  /// The store's logo if it has one, else the person's avatar.
  String? get sellerImageUrl =>
      (sellerLogoUrl?.isNotEmpty ?? false) ? sellerLogoUrl : sellerAvatarUrl;

  /// Ports `canConfirmReceipt`.
  ///
  /// The old rule demanded `shipmentStatus == 'shipped'` *and* a courier
  /// history saying delivered, so the button vanished the moment the
  /// shipment flipped to `received` — which is exactly when a buyer goes
  /// looking for it. Web accepts either a delivery timestamp or the
  /// `received` state, and additionally lets an untrackable manual courier
  /// be confirmed a day after dispatch, since no history is ever coming.
  bool canConfirmReceiptAt([DateTime? now]) {
    if (isUnpaid) return false;
    if (deliveredAt != null ||
        shipmentStatus == 'received' ||
        latestBiteshipStatus(statusHistory) == 'delivered') {
      return true;
    }
    final shipped = shippedAt;
    if (isUntrackableManual && shipped != null) {
      return (now ?? DateTime.now()).isAfter(
        shipped.add(untrackableConfirmDelay),
      );
    }
    return false;
  }

  bool get canConfirmReceipt => canConfirmReceiptAt();

  /// Ports `isUntrackableManual` — a hand-entered resi on a courier whose
  /// tracking the platform can't read, so no status will ever arrive.
  bool get isUntrackableManual =>
      originCollectionMethod == 'manual' &&
      untrackableCourierCodes.contains(courier?.trim().toLowerCase());

  /// `order_items.id` of the first line — what `confirm_receipt` takes.
  int? get firstItemId => items.isEmpty ? null : items.first.id;

  /// The settlement status the seller list buckets on. Read off the first
  /// item: every item of one order shares a checkout, so they share it.
  String? get transactionStatus =>
      items.isEmpty ? null : items.first.settlementStatus;

  String? get itemStatusRaw => items.isEmpty ? null : items.first.statusRaw;

  /// The status to reason about, which is the *item's*.
  ///
  /// `orders.status` lags: a delivered, released, fully finished order can
  /// still read `awaiting_shipment` on the package row. Anything asking
  /// "is this done?" has to go through here.
  String get effectiveStatus => itemStatusRaw ?? status.raw;

  /// `REVIEWABLE_MATCH_STATUSES` — settled well enough to rate.
  bool get isSettledSuccessfully =>
      effectiveStatus == 'completed' || effectiveStatus == 'resolved';

  /// A cancellation waiting on the seller, from whichever item carries it.
  String? get cancelStatus {
    for (final item in items) {
      if (item.cancelStatus != null) return item.cancelStatus;
    }
    return null;
  }

  /// The open dispute on any item of this order.
  ({String? slug, String? status})? get openDispute {
    for (final item in items) {
      if (item.dispute != null) return item.dispute;
    }
    return null;
  }

  String? get disputeStatus => openDispute?.status;

  /// The open invoice behind this order, when there is one to pay.
  String? get invoiceUrl {
    for (final item in items) {
      final url = item.invoiceUrl;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  /// When the buyer's payment window closes.
  DateTime? get paymentDeadline =>
      items.isEmpty ? null : items.first.paymentDeadline;

  /// Nothing has been paid for yet — the invoice is still open. Payment is
  /// recorded by `settlements.paid_at`, not by a status: the status tracks
  /// the escrow's lifecycle, which starts before the money arrives.
  bool get isUnpaid =>
      items.isNotEmpty &&
      items.every(
        (item) =>
            item.paidAt == null &&
            (item.settlementStatus == null ||
                item.settlementStatus == 'awaiting_payment'),
      );

  /// Which tab of the Pesanan list this order belongs under — a port of
  /// web's `bucketMatch`.
  ///
  /// Switches on `order_items.status`, which is what web reads. `orders.status`
  /// lags behind it: a delivered, released, fully finished order can still sit
  /// at `awaiting_shipment` on the package row, and bucketing on that filed
  /// finished orders under Diproses with a "Selesai" badge on them.
  OrderTab get tab {
    if (openDispute != null) return OrderTab.dispute;

    final deadline = paymentDeadline;
    if (isUnpaid) {
      final expired = deadline != null && deadline.isBefore(DateTime.now());
      return expired ? OrderTab.cancelled : OrderTab.unpaid;
    }

    final dispatched = switch (shipmentStatus) {
      'shipped' || 'received' || 'completed' => true,
      _ => false,
    };

    return switch (itemStatusRaw ?? status.raw) {
      'shipped' => OrderTab.shipped,
      'completed' || 'resolved' => OrderTab.completed,
      'cancelled' ||
      'expired' ||
      'rejected' ||
      'refunded' => OrderTab.cancelled,
      _ => dispatched ? OrderTab.shipped : OrderTab.processing,
    };
  }

  int get total =>
      items.fold(0, (sum, item) => sum + item.subtotal + item.shippingCost);

  int get totalQuantity =>
      items.fold(0, (sum, item) => sum + item.matchedQuantity);

  OrderModel withSeller({
    String? username,
    String? avatarUrl,
    String? logoUrl,
    String? slug,
  }) {
    return OrderModel(
      slug: this.slug,
      orderNumber: orderNumber,
      storeName: storeName,
      sellerId: sellerId,
      status: status,
      createdAt: createdAt,
      items: items,
      trackingNumber: trackingNumber,
      courier: courier,
      shipmentStatus: shipmentStatus,
      shipmentDeadline: shipmentDeadline,
      biteshipOrderId: biteshipOrderId,
      biteshipBookError: biteshipBookError,
      originCollectionMethod: originCollectionMethod,
      statusHistory: statusHistory,
      shippedAt: shippedAt,
      deliveredAt: deliveredAt,
      destination: destination,
      sellerUsername: username,
      sellerAvatarUrl: avatarUrl,
      sellerLogoUrl: logoUrl,
      sellerSlug: slug,
    );
  }
}

List<ShipmentStatusEntry>? _statusHistory(Object? raw) {
  if (raw is! List) return null;
  return [
    for (final entry in raw)
      if (entry is Map<String, dynamic>)
        ShipmentStatusEntry(
          status: entry['status'] as String?,
          at: DateTime.tryParse(entry['at'] as String? ?? '')?.toLocal(),
          note: entry['note'] as String?,
        ),
  ];
}
