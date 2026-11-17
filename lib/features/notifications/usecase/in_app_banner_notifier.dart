import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../repository/models/notification_model.dart';

/// How long a banner stays up before it slides away on its own.
const inAppBannerDuration = Duration(seconds: 4);

/// The notification the in-app banner is showing, or null when none is.
///
/// One at a time, and no queue: a newer row replaces the one on screen and
/// restarts the clock. A busy conversation would otherwise stack a banner
/// per message and keep them coming long after the user had read them —
/// every row is still in the inbox either way.
class InAppBannerNotifier extends Notifier<NotificationModel?> {
  Timer? _timer;

  @override
  NotificationModel? build() {
    // Follows the session: a banner left up across sign-out would point at
    // a row the next account can't read.
    ref.watch(authProvider.select((a) => a.valueOrNull?.id));
    ref.onDispose(_cancel);
    _cancel();
    return null;
  }

  void show(NotificationModel notification) {
    _cancel();
    state = notification;
    _timer = Timer(inAppBannerDuration, dismiss);
  }

  void dismiss() {
    _cancel();
    state = null;
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

final inAppBannerProvider =
    NotifierProvider<InAppBannerNotifier, NotificationModel?>(
      InAppBannerNotifier.new,
    );
