/// `disputes.current_status` check constraint.
enum DisputeStatus { opened, awaitingSeller, awaitingBuyer, adminReview, escalated, resolved, closed }

extension DisputeStatusX on DisputeStatus {
  String get label {
    switch (this) {
      case DisputeStatus.opened:
        return 'Dibuka';
      case DisputeStatus.awaitingSeller:
        return 'Menunggu Respons Penjual';
      case DisputeStatus.awaitingBuyer:
        return 'Menunggu Respons Pembeli';
      case DisputeStatus.adminReview:
        return 'Ditinjau Admin';
      case DisputeStatus.escalated:
        return 'Dieskalasi';
      case DisputeStatus.resolved:
        return 'Diselesaikan';
      case DisputeStatus.closed:
        return 'Ditutup';
    }
  }
}

/// `disputes.reason_category` check constraint.
enum DisputeReasonCategory { notReceived, notAsDescribed, damaged, short_ }

extension DisputeReasonCategoryX on DisputeReasonCategory {
  String get label {
    switch (this) {
      case DisputeReasonCategory.notReceived:
        return 'Barang tidak sampai';
      case DisputeReasonCategory.notAsDescribed:
        return 'Barang tidak sesuai deskripsi';
      case DisputeReasonCategory.damaged:
        return 'Barang rusak saat pengiriman';
      case DisputeReasonCategory.short_:
        return 'Jumlah barang kurang';
    }
  }
}

/// `disputes.outcome` check constraint.
enum DisputeOutcome { refundBuyer, releaseSeller, partialRefund, returnToSeller }

extension DisputeOutcomeX on DisputeOutcome {
  String get label {
    switch (this) {
      case DisputeOutcome.refundBuyer:
        return 'Dana dikembalikan ke pembeli';
      case DisputeOutcome.releaseSeller:
        return 'Dana dicairkan ke penjual';
      case DisputeOutcome.partialRefund:
        return 'Refund sebagian';
      case DisputeOutcome.returnToSeller:
        return 'Barang dikembalikan ke penjual';
    }
  }
}

/// `dispute_events.event_type` check constraint.
enum DisputeEventType {
  opened,
  evidenceSubmitted,
  adminAssigned,
  escalated,
  messagePosted,
  refundIssued,
  statusChanged,
  resolved,
  closed,
  partialRefundProposed,
  partialRefundAccepted,
  partialRefundRejected,
  returnRequested,
  returnTrackingSubmitted,
  returnReceived,
  autoResolved,
}

class DisputeEvent {
  const DisputeEvent({
    required this.type,
    required this.actorRole,
    required this.description,
    required this.createdAt,
  });

  final DisputeEventType type;

  /// `dispute_events.actor_role`: buyer/seller/admin/system.
  final String actorRole;
  final String description;
  final DateTime createdAt;
}

/// A dispute opened on an order item, mirroring `public.disputes` in
/// `supabase/migrations/00000000000000_baseline.sql`.
class DisputeModel {
  const DisputeModel({
    required this.slug,
    required this.orderSlug,
    required this.currentStatus,
    required this.reasonCategory,
    required this.reason,
    required this.openedAt,
    required this.events,
    this.outcome,
    this.proposedRefundAmount,
    this.responseDeadline,
  });

  final String slug;
  final String orderSlug;
  final DisputeStatus currentStatus;
  final DisputeReasonCategory reasonCategory;
  final String reason;
  final DateTime openedAt;
  final List<DisputeEvent> events;
  final DisputeOutcome? outcome;
  final int? proposedRefundAmount;
  final DateTime? responseDeadline;
}
