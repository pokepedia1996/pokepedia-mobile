import '../repository/models/order_model.dart';
import 'order_status_display.dart';

/// `DISPUTE_CATEGORIES` in `features/disputes/utils/dispute-reasons.ts`, in
/// the order web's `REASON_LIST` offers them.
enum DisputeReason { notReceived, damaged, notAsDescribed, short }

extension DisputeReasonX on DisputeReason {
  /// The `reason` / `reason_category` code the routes and RPCs take.
  String get raw => switch (this) {
    DisputeReason.notReceived => 'not_received',
    DisputeReason.damaged => 'damaged',
    DisputeReason.notAsDescribed => 'not_as_described',
    DisputeReason.short => 'short',
  };

  /// `categoryLabel` — the short name a filed complaint goes by.
  String get label => switch (this) {
    DisputeReason.notReceived => 'Barang tidak diterima',
    DisputeReason.damaged => 'Barang rusak',
    DisputeReason.notAsDescribed => 'Barang tidak sesuai',
    DisputeReason.short => 'Barang kurang',
  };

  /// `REASON_LIST` — how the picker phrases the option.
  String get optionLabel => switch (this) {
    DisputeReason.notReceived => 'Barang belum sampai atau tersasar',
    DisputeReason.damaged => 'Barang rusak',
    DisputeReason.notAsDescribed => 'Tidak sesuai deskripsi',
    DisputeReason.short => 'Kurang/tidak lengkap',
  };

  /// `CARD_HEADING`.
  String get itemsHeading => switch (this) {
    DisputeReason.damaged => 'Barang mana yang rusak?',
    DisputeReason.notAsDescribed => 'Barang mana yang tidak sesuai?',
    DisputeReason.short => 'Tentukan barang yang kurang',
    DisputeReason.notReceived => 'Pesanan yang belum diterima',
  };

  /// `REASON_LABEL` — the heading over the free-text field.
  String get detailLabel => switch (this) {
    DisputeReason.damaged => 'Alasan kerusakan',
    DisputeReason.notAsDescribed => 'Alasan ketidaksesuaian',
    _ => 'Alasan',
  };

  /// `RESOLUTION_INFO`.
  ({String title, String body}) get resolutionInfo => switch (this) {
    DisputeReason.notReceived => (
      title: 'Investigasi Pengiriman',
      body:
          'Tim kami akan menghubungi kurir dan menindaklanjuti pengirimanmu. '
          'Dana akan dikembalikan jika paket dikonfirmasi hilang.',
    ),
    DisputeReason.damaged => (
      title: 'Pengembalian Barang dan Dana',
      body:
          'Dana akan dikembalikan ke pembeli setelah barang bermasalah '
          'diterima oleh penjual.',
    ),
    DisputeReason.notAsDescribed => (
      title: 'Pengembalian Barang dan Dana',
      body:
          'Dana akan dikembalikan ke pembeli setelah barang yang tidak sesuai '
          'diterima oleh penjual.',
    ),
    DisputeReason.short => (
      title: 'Pengembalian Dana',
      body:
          'Dana untuk barang yang kurang akan dikembalikan ke pembeli setelah '
          'dikonfirmasi.',
    ),
  };

  /// Everything but not-received goes through `open_disputes_batch` with
  /// evidence; not-received fans out over the shipment instead.
  bool get needsEvidence => this != DisputeReason.notReceived;
}

/// `RequestedResolution` — what a damaged / not-as-described buyer asks for.
enum DisputeResolution { refundOnly, returnRefund }

extension DisputeResolutionX on DisputeResolution {
  String get raw => switch (this) {
    DisputeResolution.refundOnly => 'refund_only',
    DisputeResolution.returnRefund => 'return_refund',
  };

  /// `RESOLUTION_OPTIONS`.
  String get label => switch (this) {
    DisputeResolution.refundOnly => 'Pengembalian dana',
    DisputeResolution.returnRefund => 'Pengembalian barang',
  };

  String get body => switch (this) {
    DisputeResolution.refundOnly => 'Uang kembali, barang tetap kamu simpan.',
    DisputeResolution.returnRefund =>
      'Kirim barang kembali, uang dikembalikan.',
  };
}

/// `NOT_RECEIVED_DELIVERED_INFO` — replaces the not-received info box once the
/// courier has marked the parcel delivered.
const notReceivedDeliveredInfo = (
  title: 'Penjual akan meninjau',
  body:
      'Penjual akan menanggapi laporanmu dalam 2 hari. Kamu bisa mendapat '
      'refund, atau penjual mengirim bukti pengiriman.',
);

/// `MAX_PHOTOS`, `MAX_DETAIL`, `MAX_VIDEO_URL`, `MAX_PHOTO_SIZE` in
/// `features/disputes/utils/dispute-evidence.ts`.
const disputeMaxPhotos = 4;
const disputeMaxDetail = 1000;
const disputeMaxVideoUrl = 2048;
const disputeMaxPhotoBytes = 5 * 1024 * 1024;

/// `PHOTO_MIME_TO_EXT`, keyed the other way: the `dispute-evidence` bucket
/// only accepts these three types.
const disputePhotoMimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

/// Ports `isHttpsUrl`.
bool isHttpsUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

/// Ports `deriveOpenDisputeContext` + `computeReasonEnabled` for one order.
class OpenDisputeEligibility {
  const OpenDisputeEligibility({
    required this.snadItems,
    required this.canNotReceived,
  });

  /// `snadCards` — the items a damaged / not-as-described / short complaint
  /// may cover.
  final List<OrderItemModel> snadItems;
  final bool canNotReceived;

  bool get canSnad => snadItems.isNotEmpty;
  bool get canOpenAny => canSnad || canNotReceived;

  bool isEnabled(DisputeReason reason) =>
      reason == DisputeReason.notReceived ? canNotReceived : canSnad;
}

/// Ports `isSnadEligible`: a shipped line on a parcel the buyer could
/// confirm, with nothing already open against it.
bool isSnadEligible(OrderModel order, OrderItemModel item, {DateTime? now}) =>
    item.settlementStatus == 'shipped' &&
    order.canConfirmReceiptAt(now) &&
    item.dispute == null;

OpenDisputeEligibility openDisputeEligibility(
  OrderModel order, {
  DateTime? now,
}) {
  final hasLiveNotReceived = order.items.every(
    (item) => item.openDisputeReason == DisputeReason.notReceived.raw,
  );
  return OpenDisputeEligibility(
    snadItems: [
      for (final item in order.items)
        if (isSnadEligible(order, item, now: now)) item,
    ],
    canNotReceived:
        order.items.isNotEmpty &&
        !hasLiveNotReceived &&
        canReportNotReceived(order, now: now),
  );
}
