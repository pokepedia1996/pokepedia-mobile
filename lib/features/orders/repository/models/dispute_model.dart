import '../../../../shared/utils/postgrest_embed.dart';

/// `disputes.current_status` check constraint.
enum DisputeStatus {
  opened,
  awaitingSeller,
  awaitingBuyer,
  adminReview,
  escalated,
  resolved,
  closed,
}

extension DisputeStatusX on DisputeStatus {
  static DisputeStatus fromRaw(String? raw) => switch (raw) {
    'awaiting_seller' => DisputeStatus.awaitingSeller,
    'awaiting_buyer' => DisputeStatus.awaitingBuyer,
    'admin_review' => DisputeStatus.adminReview,
    'escalated' => DisputeStatus.escalated,
    'resolved' => DisputeStatus.resolved,
    'closed' => DisputeStatus.closed,
    _ => DisputeStatus.opened,
  };

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
  static DisputeReasonCategory fromRaw(String? raw) => switch (raw) {
    'not_received' => DisputeReasonCategory.notReceived,
    'damaged' => DisputeReasonCategory.damaged,
    'short' => DisputeReasonCategory.short_,
    _ => DisputeReasonCategory.notAsDescribed,
  };

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
enum DisputeOutcome {
  refundBuyer,
  releaseSeller,
  partialRefund,
  returnToSeller,
}

extension DisputeOutcomeX on DisputeOutcome {
  static DisputeOutcome? fromRaw(String? raw) => switch (raw) {
    'refund_buyer' => DisputeOutcome.refundBuyer,
    'release_seller' => DisputeOutcome.releaseSeller,
    'partial_refund' => DisputeOutcome.partialRefund,
    'return_to_seller' => DisputeOutcome.returnToSeller,
    _ => null,
  };

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

extension DisputeEventTypeX on DisputeEventType {
  static DisputeEventType fromRaw(String? raw) => switch (raw) {
    'evidence_submitted' => DisputeEventType.evidenceSubmitted,
    'admin_assigned' => DisputeEventType.adminAssigned,
    'escalated' => DisputeEventType.escalated,
    'message_posted' => DisputeEventType.messagePosted,
    'refund_issued' => DisputeEventType.refundIssued,
    'status_changed' => DisputeEventType.statusChanged,
    'resolved' => DisputeEventType.resolved,
    'closed' => DisputeEventType.closed,
    'partial_refund_proposed' => DisputeEventType.partialRefundProposed,
    'partial_refund_accepted' => DisputeEventType.partialRefundAccepted,
    'partial_refund_rejected' => DisputeEventType.partialRefundRejected,
    'return_requested' => DisputeEventType.returnRequested,
    'return_tracking_submitted' => DisputeEventType.returnTrackingSubmitted,
    'return_received' => DisputeEventType.returnReceived,
    'auto_resolved' => DisputeEventType.autoResolved,
    _ => DisputeEventType.opened,
  };

  /// What the timeline says when the event carries no note of its own.
  String get defaultDescription => switch (this) {
    DisputeEventType.opened => 'Sengketa dibuka.',
    DisputeEventType.evidenceSubmitted => 'Bukti diunggah.',
    DisputeEventType.adminAssigned => 'Admin ditugaskan.',
    DisputeEventType.escalated => 'Sengketa dieskalasi ke admin.',
    DisputeEventType.messagePosted => 'Pesan baru pada sengketa.',
    DisputeEventType.refundIssued => 'Refund diterbitkan.',
    DisputeEventType.statusChanged => 'Status sengketa berubah.',
    DisputeEventType.resolved => 'Sengketa diselesaikan.',
    DisputeEventType.closed => 'Sengketa ditutup.',
    DisputeEventType.partialRefundProposed => 'Refund sebagian diajukan.',
    DisputeEventType.partialRefundAccepted => 'Refund sebagian diterima.',
    DisputeEventType.partialRefundRejected => 'Refund sebagian ditolak.',
    DisputeEventType.returnRequested => 'Pengembalian barang diminta.',
    DisputeEventType.returnTrackingSubmitted => 'Resi pengembalian dikirim.',
    DisputeEventType.returnReceived => 'Barang pengembalian diterima.',
    DisputeEventType.autoResolved => 'Sengketa diselesaikan otomatis.',
  };
}

class DisputeEvent {
  /// One `dispute_events` row. The human-readable line lives in `payload`
  /// when the writer set one; otherwise the event type speaks for itself.
  factory DisputeEvent.fromRow(Map<String, dynamic> row) {
    final type = DisputeEventTypeX.fromRaw(row['event_type'] as String?);
    final payload = (row['payload'] as Map?)?.cast<String, dynamic>();
    final note =
        payload?['message'] as String? ?? payload?['description'] as String?;
    return DisputeEvent(
      type: type,
      actorRole: row['actor_role'] as String? ?? 'system',
      description: note != null && note.isNotEmpty
          ? note
          : type.defaultDescription,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

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
  factory DisputeModel.fromRow(
    Map<String, dynamic> row, {
    required String orderSlug,
  }) {
    final events =
        embeddedRows(row['dispute_events']).map(DisputeEvent.fromRow).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return DisputeModel(
      slug: row['slug'] as String? ?? '',
      orderSlug: orderSlug,
      currentStatus: DisputeStatusX.fromRaw(row['current_status'] as String?),
      reasonCategory: DisputeReasonCategoryX.fromRaw(
        row['reason_category'] as String?,
      ),
      reason: row['reason'] as String? ?? '',
      openedAt:
          DateTime.tryParse(row['opened_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      events: events,
      outcome: DisputeOutcomeX.fromRaw(row['outcome'] as String?),
      proposedRefundAmount: (row['proposed_refund_amount'] as num?)?.toInt(),
      responseDeadline: DateTime.tryParse(
        row['response_deadline_at'] as String? ?? '',
      )?.toLocal(),
    );
  }

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
