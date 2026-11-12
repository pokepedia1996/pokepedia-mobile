import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../repository/models/notification_model.dart';

/// The icon a notification is shown with — in the inbox and on the in-app
/// banner alike, so the two never disagree about what a row is.
IconData notificationIcon(NotificationType type) {
  switch (type) {
    case NotificationType.listingSold:
    case NotificationType.paymentReceived:
    case NotificationType.tradeCompleted:
    case NotificationType.orderCancelled:
    case NotificationType.shipmentPickedUp:
    case NotificationType.shipmentDelivered:
      return LucideIcons.truck;
    case NotificationType.disputeOpened:
    case NotificationType.disputeResolved:
    case NotificationType.disputeMessage:
      return LucideIcons.gavel;
    case NotificationType.bidProposalReceived:
    case NotificationType.bidProposalAccepted:
    case NotificationType.offerReceived:
    case NotificationType.offerAccepted:
    case NotificationType.offerCountered:
      return LucideIcons.tag;
    case NotificationType.ratingReceived:
      return LucideIcons.star;
    case NotificationType.chatMessage:
      return LucideIcons.messageCircle;
    case NotificationType.userReported:
      return LucideIcons.flag;
    case NotificationType.other:
      return LucideIcons.bell;
  }
}
