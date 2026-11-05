import '../repository/models/dispute_model.dart';

/// Ports `buyerActionState` in `features/disputes/domain/dispute-detail-gating.ts`
/// — which buyer panels the detail page shows for a dispute's state.
class BuyerDisputeActions {
  factory BuyerDisputeActions.of(DisputeModel d) {
    final status = d.currentStatus;
    final awaitingBuyer = status == DisputeStatus.awaitingBuyer;
    final hasPartialOffer = awaitingBuyer && (d.proposedRefundAmount ?? 0) > 0;
    // A return asked for, not yet given a deadline, tracking, or offer.
    final returnPending =
        awaitingBuyer &&
        d.returnRequestedAt != null &&
        d.returnDeadline == null &&
        d.returnTracking == null &&
        d.proposedRefundAmount == null;
    final returnApproved =
        returnPending && d.events.any((e) => e.type == 'return_approved');
    final awaitingReturnWindow = returnPending && !returnApproved;
    final needsReturnTracking =
        awaitingBuyer && d.returnDeadline != null && d.returnTracking == null;

    return BuyerDisputeActions._(
      isActive: status.isActive,
      inAdminReview: status.inAdminReview,
      answersAdminRequest: _adminAskedFor(d, 'buyer'),
      hasPartialOffer: hasPartialOffer,
      awaitingReturnWindow: awaitingReturnWindow,
      returnApproved: returnApproved,
      needsReturnTracking: needsReturnTracking,
      canRespond:
          awaitingBuyer &&
          !hasPartialOffer &&
          !awaitingReturnWindow &&
          !needsReturnTracking,
      waitingForSeller: status == DisputeStatus.awaitingSeller,
      canWithdraw:
          status.isActive &&
          !status.inAdminReview &&
          !(awaitingBuyer && d.returnTracking != null),
    );
  }

  const BuyerDisputeActions._({
    required this.isActive,
    required this.inAdminReview,
    required this.answersAdminRequest,
    required this.hasPartialOffer,
    required this.awaitingReturnWindow,
    required this.returnApproved,
    required this.needsReturnTracking,
    required this.canRespond,
    required this.waitingForSeller,
    required this.canWithdraw,
  });

  final bool isActive;
  final bool inAdminReview;
  final bool answersAdminRequest;

  /// The seller offered a partial refund; accept or reject.
  final bool hasPartialOffer;

  /// The seller asked for the card back; approve or reject.
  final bool awaitingReturnWindow;

  /// Approved, waiting for the rest of the package to be decided.
  final bool returnApproved;

  /// Return approved and its window open: send the resi.
  final bool needsReturnTracking;

  /// The buyer's turn to answer with a statement and photos.
  final bool canRespond;
  final bool waitingForSeller;
  final bool canWithdraw;
}

/// Ports `sellerActionState`.
class SellerDisputeActions {
  factory SellerDisputeActions.of(DisputeModel d) {
    final status = d.currentStatus;
    return SellerDisputeActions._(
      isActive: status.isActive,
      inAdminReview: status.inAdminReview,
      answersAdminRequest: _adminAskedFor(d, 'seller'),
      partialUsed: d.events.any((e) => e.type == 'partial_refund_proposed'),
      awaitingSellerResponse:
          status == DisputeStatus.opened ||
          status == DisputeStatus.awaitingSeller,
      awaitingReturnWindow:
          status == DisputeStatus.awaitingBuyer &&
          d.returnRequestedAt != null &&
          d.returnDeadline == null &&
          d.returnTracking == null &&
          d.proposedRefundAmount == null,
      returnInTransit:
          status == DisputeStatus.awaitingSeller && d.returnTracking != null,
      waitingForBuyer: status == DisputeStatus.awaitingBuyer,
    );
  }

  const SellerDisputeActions._({
    required this.isActive,
    required this.inAdminReview,
    required this.answersAdminRequest,
    required this.partialUsed,
    required this.awaitingSellerResponse,
    required this.awaitingReturnWindow,
    required this.returnInTransit,
    required this.waitingForBuyer,
  });

  final bool isActive;
  final bool inAdminReview;
  final bool answersAdminRequest;

  /// A partial refund was offered once already — it can't be offered again.
  final bool partialUsed;
  final bool awaitingSellerResponse;
  final bool awaitingReturnWindow;

  /// The buyer sent the card back; confirm it arrived.
  final bool returnInTransit;
  final bool waitingForBuyer;
}

bool _adminAskedFor(DisputeModel d, String role) =>
    d.currentStatus == DisputeStatus.adminReview &&
    (d.evidenceRequestedFrom == role || d.evidenceRequestedFrom == 'both');

/// A seller's ways to settle a dispute — web's `SellerAction`.
enum SellerDisputeAction {
  message('Kirim pesan & bukti'),
  fullRefund('Refund penuh ke pembeli'),
  partialRefund('Tawarkan refund sebagian'),
  requestReturn('Minta retur barang'),
  refundShortfall('Refund barang yang kurang'),
  escalate('Minta bantuan admin');

  const SellerDisputeAction(this.label);
  final String label;
}

/// Ports `getSellerOptionsAfterPartial`: what the reason allows, narrowed to
/// full refund or return once a partial offer has been turned down.
List<SellerDisputeAction> sellerDisputeOptions(
  DisputeReasonCategory reason, {
  required bool partialUsed,
}) {
  final base = switch (reason) {
    DisputeReasonCategory.notReceived => const [
      SellerDisputeAction.message,
      SellerDisputeAction.fullRefund,
      SellerDisputeAction.partialRefund,
      SellerDisputeAction.escalate,
    ],
    DisputeReasonCategory.short_ => const [
      SellerDisputeAction.message,
      SellerDisputeAction.refundShortfall,
      SellerDisputeAction.escalate,
    ],
    _ => const [
      SellerDisputeAction.message,
      SellerDisputeAction.fullRefund,
      SellerDisputeAction.partialRefund,
      SellerDisputeAction.requestReturn,
      SellerDisputeAction.escalate,
    ],
  };
  if (!partialUsed) return base;
  return base
      .where(
        (x) =>
            x == SellerDisputeAction.fullRefund ||
            x == SellerDisputeAction.requestReturn,
      )
      .toList();
}

/// The deadline the page counts down to — web's `pickSlaDeadline`.
typedef DisputeDeadline = ({DateTime at, String label, String expiredLabel});

DisputeDeadline? disputeDeadline(DisputeModel d) {
  final status = d.currentStatus;
  if (!status.isActive || status.inAdminReview) return null;
  final response = d.responseDeadline;
  if (response != null) {
    if (status == DisputeStatus.opened ||
        status == DisputeStatus.awaitingSeller) {
      return (
        at: response,
        label:
            'Batas respons ${d.role == DisputeRole.seller ? 'kamu' : 'penjual'}',
        expiredLabel: 'Lewat — dana refund ke pembeli',
      );
    }
    if ((d.proposedRefundAmount ?? 0) > 0) {
      return (
        at: response,
        label: 'Batas keputusan pembeli',
        expiredLabel: 'Lewat — refund sebagian diterima otomatis',
      );
    }
    if (d.returnRequestedAt != null) {
      return (
        at: response,
        label: 'Batas persetujuan retur',
        expiredLabel: 'Lewat — dana cair ke penjual',
      );
    }
    return (
      at: response,
      label: 'Batas respons pembeli',
      expiredLabel: 'Lewat — dana cair ke penjual',
    );
  }
  final returnDeadline = d.returnDeadline;
  if (returnDeadline != null && d.returnTracking == null) {
    return (
      at: returnDeadline,
      label: 'Batas kirim resi retur',
      expiredLabel: 'Batas retur terlewat',
    );
  }
  return null;
}

/// Ports `SellerShortfallRefundButton`'s amount: the escrow share of the
/// missing units.
int shortfallRefundAmount(DisputeModel d) {
  final matched = d.item?.matchedQuantity ?? 1;
  final short = d.shortQuantity ?? 0;
  if (matched <= 0) return 0;
  return (d.escrowAmount * short / matched).round();
}

/// Whether the page header carries "Minta bantuan admin" — the
/// `headerAction` of web's buyer and seller dispute pages. The seller's
/// action picker already offers it while it's their turn, so the header
/// doesn't repeat it then.
bool showsHeaderEscalate(DisputeModel d) {
  if (!d.currentStatus.isActive || d.currentStatus.inAdminReview) return false;
  if (d.role == DisputeRole.buyer) return true;
  final s = SellerDisputeActions.of(d);
  return !(s.awaitingSellerResponse && !s.returnInTransit);
}
