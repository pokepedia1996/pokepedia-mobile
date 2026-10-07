import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../chat/usecase/chat_notifier.dart';
import '../../notifications/usecase/notifications_notifier.dart';
import 'buyer_action_notifier.dart';

/// Web's `accountIndicator` in `mobile-bottom-nav.tsx`: the Akun tab lights
/// up when anything under it wants attention.
bool showsAccountIndicator({
  required bool signedIn,
  required int buyerActionTotal,
  required int notificationUnread,
  required int chatUnread,
}) {
  if (!signedIn) return false;
  return buyerActionTotal + notificationUnread + chatUnread > 0;
}

/// Whether the bottom nav draws the dot on Akun.
///
/// Gated on the session as well as the counts: a signed-out visitor has
/// nothing under Akun to act on, and a count left over from the previous
/// session must not outlive it.
final accountNavIndicatorProvider = Provider<bool>((ref) {
  return showsAccountIndicator(
    signedIn: ref.watch(authProvider).valueOrNull != null,
    buyerActionTotal: ref.watch(buyerActionCountsProvider).total,
    notificationUnread: ref.watch(unreadNotificationCountProvider),
    chatUnread: ref.watch(chatUnreadCountProvider),
  );
});
