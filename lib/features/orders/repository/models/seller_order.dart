import 'order_model.dart';

/// Ports `lib/shipping/biteship/statuses.ts` — the courier states, in the
/// order Biteship moves through them. The index breaks ties when two history
/// entries carry the same timestamp.
const _biteshipStatuses = [
  'confirmed',
  'scheduled',
  'allocated',
  'picking_up',
  'picked',
  'in_transit',
  'dropping_off',
  'delivered',
  'cancelled',
  'rejected',
  'courier_not_found',
  'driver_not_found',
  'on_hold',
  'problem',
  'failed_pickup',
  'delivery_exception',
  'return_in_transit',
  'returned',
  'disposed',
];

/// Ports `normalizeBiteshipStatus`. Biteship has sent camelCase, kebab and
/// spaced variants of the same state, so anything that isn't a known status
/// after normalising is discarded rather than guessed at.
String? normalizeBiteshipStatus(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final snake = raw
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .replaceAll(RegExp(r'[-\s]+'), '_')
      .toLowerCase();
  return _biteshipStatuses.contains(snake) ? snake : null;
}

/// One entry of `shipments.status_history`.
class ShipmentStatusEntry {
  const ShipmentStatusEntry({this.status, this.at});

  final String? status;
  final DateTime? at;
}

/// Ports `latestBiteshipStatus` — the most recent recognisable courier state,
/// by timestamp, with the pipeline order breaking ties.
String? latestBiteshipStatus(List<ShipmentStatusEntry>? history) {
  if (history == null || history.isEmpty) return null;

  String? latest;
  DateTime? latestAt;
  var latestIndex = -1;

  for (final entry in history) {
    final status = normalizeBiteshipStatus(entry.status);
    final at = entry.at;
    if (status == null || at == null) continue;

    final index = _biteshipStatuses.indexOf(status);
    if (latestAt == null ||
        at.isAfter(latestAt) ||
        (at.isAtSameMomentAs(latestAt) && index > latestIndex)) {
      latest = status;
      latestAt = at;
      latestIndex = index;
    }
  }
  return latest;
}

/// Ports `ACTIVE_DISPUTE_STATUSES` — a dispute in any of these still needs
/// somebody to act.
const activeDisputeStatuses = {
  'opened',
  'awaiting_seller',
  'awaiting_buyer',
  'admin_review',
  'escalated',
};

bool isDisputeOpen(String? disputeStatus) =>
    disputeStatus != null && activeDisputeStatuses.contains(disputeStatus);

const _failedMatchStatus = {'cancelled', 'expired', 'rejected', 'refunded'};
const _successMatchStatus = {'completed', 'resolved'};
const _awaitingShipmentStatus = {'awaiting_shipment', 'awaiting_pickup'};

/// Ports `SELLER_ORDER_TABS` — the tab strip, its per-tab page copy, and the
/// empty state that goes with each.
enum SellerOrderTab {
  all(
    'Semua',
    'Kelola pesanan',
    'Pantau semua status pesanan di satu tempat.',
    'Belum ada pesanan',
    'Pesanan dari pembeli akan muncul di sini.',
  ),
  awaitingPayment(
    'Menunggu pembayaran',
    'Menunggu pembayaran',
    'Pembeli belum melunasi. Pesanan otomatis dibatalkan saat batas waktu '
        'habis.',
    'Tidak ada pesanan menunggu pembayaran',
    'Pesanan yang menunggu pembayaran pembeli akan muncul di sini.',
  ),
  urgent(
    'Perlu dikirim',
    'Pesanan perlu dikirim',
    'Segera kirim sebelum batas waktu habis.',
    'Tidak ada pesanan yang perlu dikirim',
    null,
  ),
  inTransit(
    'Dalam pengiriman',
    'Pesanan dalam pengiriman',
    'Paket sedang dikirim ke alamat pembeli.',
    'Tidak ada paket dalam pengiriman',
    null,
  ),
  arrived(
    'Tiba di pembeli',
    'Pesanan tiba di pembeli',
    'Tunggu konfirmasi pembeli atau buka komplain bila perlu.',
    'Tidak ada paket tiba di tujuan',
    null,
  ),
  success(
    'Selesai',
    'Pesanan selesai',
    'Pesanan selesai dengan dana sudah dirilis.',
    'Belum ada pesanan berhasil',
    null,
  ),
  cancelRequested(
    'Permintaan batal',
    'Permintaan pembatalan',
    'Pembeli minta batalkan pesanan. Setujui atau tolak.',
    'Tidak ada permintaan pembatalan',
    null,
  ),
  failed(
    'Dibatalkan',
    'Pesanan dibatalkan',
    'Pesanan yang sudah dibatalkan, kedaluwarsa, ditolak, atau gagal '
        'diproses.',
    'Tidak ada riwayat pembatalan',
    null,
  ),
  disputed(
    'Komplain',
    'Pesanan dikomplain',
    'Tanggapi pembeli untuk menyelesaikan komplain.',
    'Tidak ada komplain aktif',
    null,
  );

  const SellerOrderTab(
    this.label,
    this.headerTitle,
    this.headerSubtitle,
    this.emptyHeadline,
    this.emptySub,
  );

  final String label;
  final String headerTitle;
  final String headerSubtitle;
  final String emptyHeadline;
  final String? emptySub;

  /// Web badges these in the seller sidebar: each one is waiting on the
  /// seller to do something.
  bool get isUrgent =>
      this == SellerOrderTab.awaitingPayment ||
      this == SellerOrderTab.urgent ||
      this == SellerOrderTab.cancelRequested ||
      this == SellerOrderTab.disputed;
}

/// Ports `tabMatchesRow`. Note what "Semua" does *not* include: an unpaid
/// checkout isn't an order the seller can act on, so it only appears under
/// its own tab.
bool tabMatchesSellerOrder(SellerOrderTab tab, SellerOrderTab? bucket) {
  if (tab == SellerOrderTab.all) {
    return bucket != SellerOrderTab.awaitingPayment;
  }
  return tab == bucket;
}

/// Ports `bucketSellerRow` — which tab an order falls under.
///
/// Order matters here and the rules are not mutually exclusive: a cancelled
/// order that came back to the seller is a *success* (the return completed),
/// and a dispute outranks whatever the shipment says, because the shipment
/// being "delivered" is exactly what's being argued about.
SellerOrderTab? bucketSellerOrder(OrderModel order) {
  if (order.cancelStatus == 'pending_seller') {
    return SellerOrderTab.cancelRequested;
  }
  if (isDisputeOpen(order.disputeStatus)) return SellerOrderTab.disputed;

  final matchStatus = order.itemStatusRaw;
  final latest = latestBiteshipStatus(order.statusHistory);
  final isReturnFlow = latest == 'returned';

  if (isReturnFlow && matchStatus == 'cancelled') return SellerOrderTab.success;
  if (isReturnFlow && order.shipmentStatus == 'issue') {
    return SellerOrderTab.arrived;
  }

  if (_successMatchStatus.contains(matchStatus)) return SellerOrderTab.success;
  if (_failedMatchStatus.contains(matchStatus)) return SellerOrderTab.failed;

  if (order.transactionStatus == 'awaiting_payment') {
    return SellerOrderTab.awaitingPayment;
  }

  // A booking that failed and was never retried is dead: the courier has no
  // record of it, so it can't move on its own.
  final bookError = order.biteshipBookError;
  if (bookError != null &&
      order.biteshipOrderId == null &&
      !bookError.startsWith('seller_cancel')) {
    return SellerOrderTab.failed;
  }

  if (order.shipmentStatus == 'shipped') return SellerOrderTab.inTransit;
  if (order.shipmentStatus == 'received') return SellerOrderTab.arrived;

  final shipmentStatus = order.shipmentStatus;
  if (shipmentStatus != null &&
      _awaitingShipmentStatus.contains(shipmentStatus)) {
    return SellerOrderTab.urgent;
  }

  return null;
}

/// How the seller's list is ordered. Ports web's `SORT_OPTIONS`.
enum SellerOrderSort {
  newest('Terbaru'),
  oldest('Terlama'),
  priceDesc('Harga tertinggi'),
  deadline('Deadline terdekat');

  const SellerOrderSort(this.label);

  final String label;

  List<OrderModel> apply(List<OrderModel> orders) {
    final sorted = [...orders];
    switch (this) {
      case SellerOrderSort.oldest:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case SellerOrderSort.priceDesc:
        sorted.sort((a, b) => b.total.compareTo(a.total));
      case SellerOrderSort.deadline:
        // Orders with no deadline sort last rather than first: "soonest"
        // shouldn't be led by rows that have no clock running at all.
        sorted.sort((a, b) {
          final aAt = a.shipmentDeadline;
          final bAt = b.shipmentDeadline;
          if (aAt == null && bAt == null) return 0;
          if (aAt == null) return 1;
          if (bAt == null) return -1;
          return aAt.compareTo(bAt);
        });
      case SellerOrderSort.newest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return sorted;
  }
}
