import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
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

  /// Ports `ACTIVE_DISPUTE_STATUSES`.
  bool get isActive =>
      this != DisputeStatus.resolved && this != DisputeStatus.closed;

  /// Admin holds the dispute; neither party acts until it decides.
  bool get inAdminReview =>
      this == DisputeStatus.adminReview || this == DisputeStatus.escalated;
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

/// Which side of the dispute the viewer is on — decides which actions show.
enum DisputeRole { buyer, seller }

/// Ports `EVENT_LABEL` in `dispute-timeline.tsx`. Keyed by the raw
/// `dispute_events.event_type`, since the RPCs add types (`return_approved`,
/// `admin_message`, …) faster than a closed enum would keep up with.
const _eventLabels = {
  'opened': 'Komplain dibuka pembeli',
  'evidence_submitted': 'Bukti dikirim',
  'partial_refund_proposed': 'Penjual menawarkan refund sebagian',
  'partial_refund_accepted': 'Pembeli menerima refund sebagian',
  'partial_refund_rejected': 'Pembeli menolak refund sebagian',
  'return_requested': 'Penjual meminta retur barang',
  'return_tracking_submitted': 'Pembeli mengirim resi retur',
  'return_received': 'Penjual mengonfirmasi barang diterima',
  'return_approved': 'Pembeli menyetujui retur',
  'return_rejected': 'Pembeli menolak retur',
  'return_window_started': 'Jendela retur dibuka',
  'message_posted': 'Pesan dikirim',
  'admin_message': 'Pesan dari admin',
  'evidence_requested': 'Admin meminta bukti',
  'status_changed': 'Status berubah',
  'admin_assigned': 'Admin ditugaskan',
  'escalated': 'Dieskalasi ke admin',
  'refund_issued': 'Refund dikeluarkan',
  'resolved': 'Komplain selesai',
  'closed': 'Komplain ditutup',
  'auto_resolved': 'Diselesaikan otomatis sistem',
};

const _outcomeLabels = {
  'refund_buyer': 'Refund ke pembeli',
  'release_seller': 'Dana diteruskan ke penjual',
  'partial_refund': 'Refund sebagian',
  'return_to_seller': 'Retur ke penjual',
};

class DisputeEvent {
  /// One `dispute_events` row.
  factory DisputeEvent.fromRow(Map<String, dynamic> row) => DisputeEvent(
    type: row['event_type'] as String? ?? '',
    actorRole: row['actor_role'] as String?,
    payload: (row['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    createdAt:
        DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );

  const DisputeEvent({
    required this.type,
    required this.createdAt,
    this.actorRole,
    this.payload = const {},
  });

  /// `dispute_events.event_type`, raw.
  final String type;

  /// `dispute_events.actor_role`: buyer/seller/admin/system.
  final String? actorRole;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  String get label => _eventLabels[type] ?? type;

  /// Ports `describePayload` — the detail line under the label, when the
  /// event carries one worth reading.
  String? get detail {
    final p = payload;
    final amount = p['amount'];
    switch (type) {
      case 'partial_refund_proposed' when amount is num:
        return 'Tawaran ${formatRupiah(amount.toInt())}';
      case 'partial_refund_accepted' when amount is num:
        return 'Diterima ${formatRupiah(amount.toInt())}';
      case 'partial_refund_rejected' when amount is num:
        return 'Tawaran ditolak: ${formatRupiah(amount.toInt())}';
      case 'return_tracking_submitted':
        final courier = p['courier'], tracking = p['tracking'];
        if (courier is String && tracking is String) {
          return '${courier.toUpperCase()} · $tracking';
        }
      case 'return_requested':
        final deadline = DateTime.tryParse(p['deadline_at'] as String? ?? '');
        if (deadline != null) {
          return 'Batas resi: ${formatDeadlineId(deadline)}';
        }
      case 'resolved':
        final outcome = p['outcome'];
        if (outcome is String) return _outcomeLabels[outcome] ?? outcome;
      case 'escalated' when p['reason'] is String:
        if (p['reason'] == 'sla_breach') {
          return 'Pihak lawan tidak merespons batas waktu';
        }
        return p['escalated_by'] == 'buyer'
            ? 'Dieskalasi oleh pembeli'
            : 'Dieskalasi oleh penjual';
    }
    return null;
  }
}

/// One `dispute_evidence` row. Photo URLs arrive signed — the bucket is
/// private, and the stored public-form URL is only an identifier.
class DisputeEvidence {
  factory DisputeEvidence.fromRow(Map<String, dynamic> row) => DisputeEvidence(
    id: (row['id'] as num?)?.toInt() ?? 0,
    role: row['submitted_by_role'] as String? ?? '',
    type: row['evidence_type'] as String? ?? '',
    url: row['url'] as String?,
    body: row['body'] as String?,
    submittedAt: row['submitted_at'] as String? ?? '',
  );

  const DisputeEvidence({
    required this.id,
    required this.role,
    required this.type,
    required this.submittedAt,
    this.url,
    this.body,
  });

  final int id;

  /// buyer/seller/admin.
  final String role;

  /// statement/photo/video.
  final String type;
  final String? url;
  final String? body;

  /// Kept as the raw string: rows written together share it exactly, and
  /// that is what groups them into one message.
  final String submittedAt;

  DisputeEvidence withUrl(String? url) => DisputeEvidence(
    id: id,
    role: role,
    type: type,
    submittedAt: submittedAt,
    url: url,
    body: body,
  );
}

/// One message in "Diskusi & bukti": the evidence rows a party sent
/// together — web's `groupIntoMessages`.
class DisputeMessage {
  const DisputeMessage({
    required this.role,
    required this.submittedAt,
    this.statement,
    this.photoUrls = const [],
    this.videoUrls = const [],
  });

  final String role;
  final DateTime submittedAt;
  final String? statement;
  final List<String> photoUrls;
  final List<String> videoUrls;
}

List<DisputeMessage> groupDisputeMessages(List<DisputeEvidence> evidence) {
  final groups = <String, List<DisputeEvidence>>{};
  for (final e in evidence) {
    groups.putIfAbsent('${e.role}|${e.submittedAt}', () => []).add(e);
  }
  final ordered = groups.values.toList()
    ..sort((a, b) {
      final t = a.first.submittedAt.compareTo(b.first.submittedAt);
      if (t != 0) return t;
      int firstId(List<DisputeEvidence> rows) =>
          rows.map((r) => r.id).reduce((x, y) => x < y ? x : y);
      return firstId(a).compareTo(firstId(b));
    });
  return [
    for (final rows in ordered)
      DisputeMessage(
        role: rows.first.role,
        submittedAt:
            DateTime.tryParse(rows.first.submittedAt)?.toLocal() ??
            DateTime.now(),
        statement: rows
            .where((r) => r.type == 'statement' && (r.body ?? '').isNotEmpty)
            .map((r) => r.body)
            .lastOrNull,
        photoUrls: [
          for (final r in rows)
            if (r.type == 'photo' && r.url != null) r.url!,
        ],
        videoUrls: [
          for (final r in rows)
            if (r.type == 'video' && (r.url ?? '').startsWith('https://'))
              r.url!,
        ],
      ),
  ];
}

/// The disputed line: which card, how many, and the order it sits in.
class DisputeItem {
  const DisputeItem({
    required this.slug,
    required this.cardName,
    this.cardId,
    this.orderId,
    this.cardImageUrl,
    this.expansionCode,
    this.collectorNumber,
    this.orderNumber,
    this.packageOrderNumber,
    this.matchedQuantity,
    this.matchPrice,
  });

  /// `order_items.slug` — what withdrawing a complaint is keyed by.
  final String slug;
  final String cardName;
  final int? cardId;

  /// `order_items.order_id` — the package, which sibling disputes share.
  final int? orderId;
  final String? cardImageUrl;
  final String? expansionCode;
  final String? collectorNumber;
  final String? orderNumber;

  /// The package (`orders.order_number`) this line was shipped in.
  final String? packageOrderNumber;
  final int? matchedQuantity;
  final int? matchPrice;
}

/// A dispute with everything its detail page needs, from
/// `DISPUTE_DETAIL_SELECT` in `features/disputes/data/disputes.ts`.
class DisputeModel {
  factory DisputeModel.fromRow(
    Map<String, dynamic> row, {
    required DisputeRole role,
  }) {
    final settlement = embeddedRow(row['settlements']) ?? const {};
    final item = embeddedRow(settlement['order_items']);
    final card = embeddedRow(item?['cards']);
    final events =
        embeddedRows(row['dispute_events']).map(DisputeEvent.fromRow).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    DateTime? date(String key) =>
        DateTime.tryParse(row[key] as String? ?? '')?.toLocal();
    final requestedFrom = row['evidence_requested_from'] as String?;

    return DisputeModel(
      id: (row['id'] as num?)?.toInt() ?? 0,
      slug: row['slug'] as String? ?? '',
      role: role,
      currentStatus: DisputeStatusX.fromRaw(row['current_status'] as String?),
      reasonCategory: DisputeReasonCategoryX.fromRaw(
        row['reason_category'] as String?,
      ),
      reason: row['reason'] as String? ?? '',
      shortQuantity: (row['short_quantity'] as num?)?.toInt(),
      requestedResolution: row['requested_resolution'] as String?,
      openedAt: date('opened_at') ?? DateTime.now(),
      resolvedAt: date('resolved_at'),
      outcome: DisputeOutcomeX.fromRaw(row['outcome'] as String?),
      proposedRefundAmount: (row['proposed_refund_amount'] as num?)?.toInt(),
      responseDeadline: date('response_deadline_at'),
      returnCourier: row['return_courier'] as String?,
      returnTracking: row['return_tracking'] as String?,
      returnRequestedAt: date('return_requested_at'),
      returnDeadline: date('return_deadline_at'),
      evidenceRequestedFrom: requestedFrom,
      evidenceRequestDueAt: date('evidence_request_due_at'),
      settlementSlug: settlement['slug'] as String? ?? '',
      sellerId: settlement['seller_id'] as String?,
      escrowAmount: (settlement['escrow_amount'] as num?)?.toInt() ?? 0,
      shippingCost: (settlement['shipping_cost'] as num?)?.toInt() ?? 0,
      condition: settlement['condition'] is String
          ? CardConditionX.fromRaw(settlement['condition'] as String)
          : null,
      item: item == null
          ? null
          : DisputeItem(
              slug: item['slug'] as String? ?? '',
              cardName: card?['name_id'] as String? ?? 'Kartu',
              cardId: (item['card_id'] as num?)?.toInt(),
              orderId: (item['order_id'] as num?)?.toInt(),
              cardImageUrl: card?['image_url'] as String?,
              expansionCode: card?['expansion_code'] as String?,
              collectorNumber: card?['collector_number'] as String?,
              orderNumber: item['order_number'] as String?,
              packageOrderNumber:
                  embeddedRow(item['package_order'])?['order_number']
                      as String?,
              matchedQuantity: (item['matched_quantity'] as num?)?.toInt(),
              matchPrice: (item['match_price'] as num?)?.toInt(),
            ),
      events: events,
      evidence: embeddedRows(
        row['dispute_evidence'],
      ).map(DisputeEvidence.fromRow).toList(),
    );
  }

  const DisputeModel({
    required this.id,
    required this.slug,
    required this.role,
    required this.currentStatus,
    required this.reasonCategory,
    required this.reason,
    required this.openedAt,
    required this.settlementSlug,
    required this.escrowAmount,
    this.events = const [],
    this.evidence = const [],
    this.shortQuantity,
    this.requestedResolution,
    this.resolvedAt,
    this.outcome,
    this.proposedRefundAmount,
    this.responseDeadline,
    this.returnCourier,
    this.returnTracking,
    this.returnRequestedAt,
    this.returnDeadline,
    this.evidenceRequestedFrom,
    this.evidenceRequestDueAt,
    this.sellerId,
    this.shippingCost = 0,
    this.condition,
    this.item,
  });

  /// `disputes.id` — the key every `/api/disputes/[id]/*` action takes.
  final int id;
  final String slug;
  final DisputeRole role;
  final DisputeStatus currentStatus;
  final DisputeReasonCategory reasonCategory;
  final String reason;
  final int? shortQuantity;

  /// `refund_only` or `return_refund`, what the buyer asked for.
  final String? requestedResolution;
  final DateTime openedAt;
  final DateTime? resolvedAt;
  final DisputeOutcome? outcome;
  final int? proposedRefundAmount;
  final DateTime? responseDeadline;
  final String? returnCourier;
  final String? returnTracking;
  final DateTime? returnRequestedAt;
  final DateTime? returnDeadline;

  /// buyer/seller/both — who admin asked for more evidence.
  final String? evidenceRequestedFrom;
  final DateTime? evidenceRequestDueAt;

  /// `settlements.slug`: the evidence folder, and the key of
  /// `/api/settlements/[slug]/dispute-response`.
  final String settlementSlug;
  final String? sellerId;
  final int escrowAmount;
  final int shippingCost;
  final CardCondition? condition;
  final DisputeItem? item;
  final List<DisputeEvent> events;
  final List<DisputeEvidence> evidence;

  DisputeModel withEvidence(List<DisputeEvidence> evidence) => DisputeModel(
    id: id,
    slug: slug,
    role: role,
    currentStatus: currentStatus,
    reasonCategory: reasonCategory,
    reason: reason,
    openedAt: openedAt,
    settlementSlug: settlementSlug,
    escrowAmount: escrowAmount,
    events: events,
    evidence: evidence,
    shortQuantity: shortQuantity,
    requestedResolution: requestedResolution,
    resolvedAt: resolvedAt,
    outcome: outcome,
    proposedRefundAmount: proposedRefundAmount,
    responseDeadline: responseDeadline,
    returnCourier: returnCourier,
    returnTracking: returnTracking,
    returnRequestedAt: returnRequestedAt,
    returnDeadline: returnDeadline,
    evidenceRequestedFrom: evidenceRequestedFrom,
    evidenceRequestDueAt: evidenceRequestDueAt,
    sellerId: sellerId,
    shippingCost: shippingCost,
    condition: condition,
    item: item,
  );
}

/// Another unresolved dispute in the same package — web's `SiblingDispute`.
class SiblingDispute {
  const SiblingDispute({
    required this.slug,
    required this.cardName,
    required this.orderNumber,
  });

  final String slug;
  final String cardName;
  final String orderNumber;
}
