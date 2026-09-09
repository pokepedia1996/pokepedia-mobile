import '../../../shared/widgets/inline_pill.dart';
import '../repository/models/order_model.dart';

/// Ports `features/orders/utils/status-display.ts` — the one place that
/// decides what an order is called and what colour it reads in.
///
/// Mobile used to label cards straight off `OrderStatus.label`, which is the
/// raw match status. Web layers a dispute, an expired invoice and the
/// shipment's own status over that before it settles on a word, so the two
/// clients could name the same order differently.
class OrderStatusDisplay {
  const OrderStatusDisplay({
    required this.key,
    required this.label,
    required this.tone,
  });

  final String key;
  final String label;
  final InlinePillTone tone;
}

/// `MATCH_STATUS_MAP`.
const _matchStatus = <String, OrderStatusDisplay>{
  'open': OrderStatusDisplay(
    key: 'open',
    label: 'Aktif',
    tone: InlinePillTone.info,
  ),
  'matched': OrderStatusDisplay(
    key: 'matched',
    label: 'Matched',
    tone: InlinePillTone.warning,
  ),
  'awaiting_payment': OrderStatusDisplay(
    key: 'awaiting_payment',
    label: 'Menunggu Pembayaran',
    tone: InlinePillTone.warning,
  ),
  'accepted': OrderStatusDisplay(
    key: 'accepted',
    label: 'Diterima',
    tone: InlinePillTone.progress,
  ),
  'in_escrow': OrderStatusDisplay(
    key: 'in_escrow',
    label: 'Dalam Proses',
    tone: InlinePillTone.progress,
  ),
  'awaiting_shipment': OrderStatusDisplay(
    key: 'awaiting_shipment',
    label: 'Menunggu Pengiriman',
    tone: InlinePillTone.progress,
  ),
  'shipped': OrderStatusDisplay(
    key: 'shipped',
    label: 'Dikirim',
    tone: InlinePillTone.shipped,
  ),
  'completed': OrderStatusDisplay(
    key: 'completed',
    label: 'Selesai',
    tone: InlinePillTone.success,
  ),
  'resolved': OrderStatusDisplay(
    key: 'resolved',
    label: 'Diselesaikan',
    tone: InlinePillTone.success,
  ),
  'cancelled': OrderStatusDisplay(
    key: 'cancelled',
    label: 'Dibatalkan',
    tone: InlinePillTone.neutral,
  ),
  'expired': OrderStatusDisplay(
    key: 'expired',
    label: 'Kedaluwarsa',
    tone: InlinePillTone.neutral,
  ),
  'rejected': OrderStatusDisplay(
    key: 'rejected',
    label: 'Ditolak',
    tone: InlinePillTone.danger,
  ),
  'refunded': OrderStatusDisplay(
    key: 'refunded',
    label: 'Dana Dikembalikan',
    tone: InlinePillTone.info,
  ),
  'disputed': OrderStatusDisplay(
    key: 'disputed',
    label: 'Komplain',
    tone: InlinePillTone.danger,
  ),
};

/// `SHIPMENT_OVERRIDE_MAP` — where the courier's status outranks the order's.
const _shipmentOverride = <String, OrderStatusDisplay>{
  'issue': OrderStatusDisplay(
    key: 'shipment_issue',
    label: 'Bermasalah',
    tone: InlinePillTone.danger,
  ),
  'cancelled': OrderStatusDisplay(
    key: 'shipment_cancelled',
    label: 'Pengiriman Dibatalkan',
    tone: InlinePillTone.neutral,
  ),
  'received': OrderStatusDisplay(
    key: 'shipment_received',
    label: 'Tiba di Tujuan',
    tone: InlinePillTone.info,
  ),
  'awaiting_pickup': OrderStatusDisplay(
    key: 'shipment_awaiting_pickup',
    label: 'Menunggu Pickup',
    tone: InlinePillTone.progress,
  ),
};

const _unknownStatus = OrderStatusDisplay(
  key: 'unknown',
  label: 'Status tidak diketahui',
  tone: InlinePillTone.neutral,
);

OrderStatusDisplay describeMatchStatus(String status) =>
    _matchStatus[status] ?? _unknownStatus;

/// `TERMINAL_MATCH_STATUSES` — once here, nothing the shipment says matters.
const _terminalStatuses = {
  'completed',
  'resolved',
  'cancelled',
  'expired',
  'rejected',
  'refunded',
};

/// Ports `describeOrderForBuyer`, in its exact order of precedence: an open
/// dispute first, then a settled order, then an invoice that ran out, then an
/// unpaid one, then whatever the courier says, and only then the order's own
/// status.
OrderStatusDisplay describeOrderForBuyer(OrderModel order, {DateTime? now}) {
  final at = now ?? DateTime.now();

  if (order.openDispute != null) return _matchStatus['disputed']!;

  final raw = order.effectiveStatus;
  if (_terminalStatuses.contains(raw)) return describeMatchStatus(raw);

  // `isUnpaidExpired`: the invoice window closed with nothing paid.
  final deadline = order.paymentDeadline;
  if (order.isUnpaid && deadline != null && deadline.isBefore(at)) {
    return _matchStatus['expired']!;
  }
  if (order.isUnpaid) return _matchStatus['awaiting_payment']!;

  final shipment = order.shipmentStatus;
  if (shipment != null && _shipmentOverride.containsKey(shipment)) {
    return _shipmentOverride[shipment]!;
  }
  if (isShipmentDispatched(shipment) && raw != 'disputed') {
    return _matchStatus['shipped']!;
  }
  return describeMatchStatus(raw);
}

/// `isShipmentDispatched` — the package has left the seller.
bool isShipmentDispatched(String? shipmentStatus) => switch (shipmentStatus) {
  'shipped' || 'received' || 'completed' => true,
  _ => false,
};

/// `SHIPMENT_STATUS_LABEL` in `lib/shipping/fetch`.
String shipmentStatusLabel(String? status) => switch (status) {
  null => '-',
  'pending' => 'Menunggu',
  'awaiting_shipment' => 'Menunggu Pengiriman',
  'awaiting_pickup' => 'Menunggu Pickup Kurir',
  'shipped' => 'Dalam Pengiriman',
  'received' => 'Tiba di Tujuan',
  'completed' => 'Selesai',
  'cancelled' => 'Dibatalkan',
  'issue' => 'Bermasalah',
  final other => other,
};

/// `INR_WINDOW_MS` — how long after dispatch a buyer may report a package as
/// never arrived, when the courier hasn't said it landed.
const inrWindow = Duration(hours: 24);

/// Ports `canReportNotReceived`. Delivered means straight away; mid-flight
/// means only once the window has elapsed, so a parcel that left this morning
/// can't be reported missing this afternoon.
bool canReportNotReceived(OrderModel order, {DateTime? now}) {
  if (order.shipmentStatus == 'received' || order.deliveredAt != null) {
    return true;
  }
  if (order.shipmentStatus != 'shipped') return false;
  final shippedAt = order.shippedAt;
  if (shippedAt == null) return false;
  return (now ?? DateTime.now()).isAfter(shippedAt.add(inrWindow));
}

/// The buyer detail's states, resolved once so the page doesn't recompute
/// the same predicates at four call sites and drift between them.
///
/// Mirrors the block at the top of web's `order-detail.tsx`.
class BuyerOrderStates {
  BuyerOrderStates(this.order, {DateTime? now}) : _now = now ?? DateTime.now();

  final OrderModel order;
  final DateTime _now;

  bool get disputeOpen => order.openDispute != null;
  bool get isUnpaid => order.isUnpaid;

  /// `showCancelPending` — a cancellation the seller hasn't answered.
  bool get cancelPending => order.cancelStatus == 'pending_seller';

  /// `showPreparing` — strictly `shipment.status === 'awaiting_shipment'`.
  ///
  /// A missing shipment is *not* "being prepared": a cancelled or expired
  /// order has no shipment row either, and treating null as preparing told
  /// those buyers the seller was packing an order that no longer exists.
  bool get preparing =>
      !isUnpaid && !disputeOpen && order.shipmentStatus == 'awaiting_shipment';

  /// `isShipped` — the *settlement's* status, as web reads it.
  ///
  /// Not the shipment's: that stays `received`/`completed` after delivery, so
  /// keying on it left a finished order still offering "Ajukan Komplain" and
  /// the confirm-receipt hints long after it was done.
  bool get isShipped => order.transactionStatus == 'shipped';

  /// Reads the item, not `orders.status`, which lags behind it — a
  /// finished order was reporting false here and losing its tracking
  /// section.
  bool get isCompleted => order.isSettledSuccessfully;
  bool get hasTracking => (order.statusHistory?.isNotEmpty ?? false);

  /// `showLacakPaket`. Note it does *not* require a tracking number: a
  /// dispatched parcel gets the section even before a resi exists, which is
  /// where mobile's "only when trackingNumber != null" gate hid it.
  bool get showTracking => isShipped || isCompleted || hasTracking;

  /// `canConfirm` — the server refuses anything else, so the button follows.
  bool get canConfirm => order.canConfirmReceipt;

  /// `showReport` / `reportActive`.
  bool get showReport => isShipped && !disputeOpen;
  bool get reportActive =>
      showReport && (canConfirm || canReportNotReceived(order, now: _now));

  /// `isAwaitingShipment` — the settlement, not `orders.status`.
  bool get _awaitingShipment => order.transactionStatus == 'awaiting_shipment';

  /// `isInProcess`: the seller has handed the parcel to a courier. Once a
  /// booking exists the cancellation is no longer the buyer's to make — the
  /// resi is already out there.
  bool get _dispatchStarted {
    final shipment = order.shipmentStatus;
    return shipment != null && shipment != 'awaiting_shipment';
  }

  /// `cancelBlocked`. `cancelStatus != null` covers a request already
  /// pending, so [cancelPending] does not need repeating here.
  bool get _cancelBlocked =>
      order.cancelStatus != null ||
      isCompleted ||
      order.effectiveStatus == 'cancelled';

  /// Whether "Batalkan Pesanan" does anything.
  bool get canRequestCancel =>
      _awaitingShipment && !_dispatchStarted && !_cancelBlocked;

  /// Web still *renders* the button once a resi exists, greyed out, rather
  /// than removing it — so the option reads as spent rather than absent.
  bool get showDisabledCancel =>
      _awaitingShipment && _dispatchStarted && !_cancelBlocked;
}
