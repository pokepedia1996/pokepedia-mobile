import '../../../../core/utils/formatters.dart';

/// `notifications.category` — the `public.notification_category` Postgres
/// enum in `supabase/migrations/00000000000000_baseline.sql`.
enum NotificationCategory { actionRequired, statusUpdate, social, admin }

/// A curated, buyer-relevant subset of `notifications.type`'s ~48-value
/// check constraint — the full list also covers seller/admin-only events
/// out of scope for this pass.
enum NotificationType {
  listingSold,
  paymentReceived,
  tradeCompleted,
  orderCancelled,
  shipmentPickedUp,
  shipmentDelivered,
  disputeOpened,
  disputeResolved,
  disputeMessage,
  bidProposalReceived,
  bidProposalAccepted,
  offerReceived,
  offerAccepted,
  offerCountered,
  ratingReceived,
  chatMessage,

  /// Anything outside the curated list above — still shown, just with the
  /// generic icon. The constraint carries ~48 types and grows server-side.
  other,
}

extension NotificationTypeX on NotificationType {
  String get raw {
    switch (this) {
      case NotificationType.listingSold:
        return 'listing_sold';
      case NotificationType.paymentReceived:
        return 'payment_received';
      case NotificationType.tradeCompleted:
        return 'trade_completed';
      case NotificationType.orderCancelled:
        return 'order_cancelled';
      case NotificationType.shipmentPickedUp:
        return 'shipment_picked_up';
      case NotificationType.shipmentDelivered:
        return 'shipment_delivered';
      case NotificationType.disputeOpened:
        return 'dispute_opened';
      case NotificationType.disputeResolved:
        return 'dispute_resolved';
      case NotificationType.disputeMessage:
        return 'dispute_message';
      case NotificationType.bidProposalReceived:
        return 'bid_proposal_received';
      case NotificationType.bidProposalAccepted:
        return 'bid_proposal_accepted';
      case NotificationType.offerReceived:
        return 'offer_received';
      case NotificationType.offerAccepted:
        return 'offer_accepted';
      case NotificationType.offerCountered:
        return 'offer_countered';
      case NotificationType.ratingReceived:
        return 'rating_received';
      case NotificationType.chatMessage:
        return 'chat_message';
      case NotificationType.other:
        return 'other';
    }
  }

  /// Parses `notifications.type`, falling back rather than throwing on a
  /// type the app doesn't name.
  static NotificationType fromRaw(String? raw) {
    for (final type in NotificationType.values) {
      if (type != NotificationType.other && type.raw == raw) return type;
    }
    return NotificationType.other;
  }
}

extension NotificationCategoryX on NotificationCategory {
  static NotificationCategory fromRaw(String? raw) => switch (raw) {
    'action_required' => NotificationCategory.actionRequired,
    'social' => NotificationCategory.social,
    'admin' => NotificationCategory.admin,
    _ => NotificationCategory.statusUpdate,
  };
}

class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.slug,
    required this.type,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.actionUrl,
  });

  factory NotificationModel.fromRow(Map<String, dynamic> row) {
    return NotificationModel(
      id: (row['id'] as num).toInt(),
      slug: row['slug'] as String? ?? '',
      type: NotificationTypeX.fromRaw(row['type'] as String?),
      category: NotificationCategoryX.fromRaw(row['category'] as String?),
      title: row['title'] as String? ?? '',
      body: row['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      isRead: row['is_read'] as bool? ?? false,
      actionUrl: row['action_url'] as String?,
    );
  }

  final int id;

  /// `notifications.slug` — the uuid `mark_notification_read` takes. The
  /// row's `id` identifies it locally; this is what the server accepts.
  final String slug;

  final NotificationType type;
  final NotificationCategory category;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  /// Where tapping the row should go, as the server wrote it — a web path
  /// like `/orders/<slug>`.
  final String? actionUrl;

  /// Against the real clock, not the dummy catalog's fixed "today".
  String get createdLabel => formatRelativeId(createdAt, now: DateTime.now());

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
    id: id,
    slug: slug,
    type: type,
    category: category,
    title: title,
    body: body,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    actionUrl: actionUrl,
  );
}
