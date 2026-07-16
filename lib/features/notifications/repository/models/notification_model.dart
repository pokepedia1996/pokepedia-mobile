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
    }
  }
}

class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
  });

  final int id;
  final NotificationType type;
  final NotificationCategory category;
  final String title;
  final String body;
  final String createdAt;
  final bool isRead;

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
    id: id,
    type: type,
    category: category,
    title: title,
    body: body,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
  );
}
