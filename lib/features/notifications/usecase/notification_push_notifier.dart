import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/router/app_router.dart';
import '../../../core/notifications/local_push.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../chat/usecase/chat_notifier.dart';
import '../repository/models/notification_model.dart';
import 'in_app_banner_notifier.dart';
import 'notification_route.dart';
import 'notifications_notifier.dart';

/// Turns a new `notifications` row into a notification the phone shows, and a
/// tap on it into a screen.
///
/// `public.notifications` is in the `supabase_realtime` publication and
/// `notifications_select_own` scopes it to the signed-in user, so the app can
/// listen for its own rows directly — the same mechanism chat already uses
/// for messages. Watch this provider once, high in the tree, and it follows
/// the session: subscribing on sign-in, tearing down on sign-out.
///
/// With the app in front, a row shows as the in-app banner rather than an
/// OS notification — see [deliveryFor].
///
/// What this is not: remote push. The row has to reach a running app, so a
/// notification raised while the process is dead is not delivered — see
/// [LocalPush] for what that would take.
class NotificationPushNotifier extends Notifier<void> {
  RealtimeChannel? _channel;
  StreamSubscription<String>? _taps;

  @override
  void build() {
    // Who is signed in, not the whole user: the profile filling in after
    // launch would otherwise tear the channel down and rejoin it on the same
    // topic for nothing.
    final userId = ref.watch(authProvider.select((a) => a.valueOrNull?.id));

    ref.onDispose(_teardown);
    if (userId == null) {
      _teardown();
      return;
    }

    unawaited(_start(userId));
  }

  Future<void> _start(String userId) async {
    await LocalPush.instance.init();
    _taps ??= LocalPush.instance.taps.listen(_openRoute);

    // A tap that launched the app happened before this listener existed, so
    // it is claimed rather than received. Only now, with the session known:
    // pushing a chat route before auth resolves lands on a room the RLS
    // policies can't yet see, which draws an empty conversation.
    final launched = LocalPush.instance.takeLaunchRoute();
    if (launched != null) _openRoute(launched);

    _channel?.unsubscribe();
    _channel = ref
        .read(supabaseClientProvider)
        .channel('notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => unawaited(_onInserted(payload.newRecord)),
        )
        .subscribe();
  }

  Future<void> _onInserted(Map<String, dynamic> row) async {
    final notification = NotificationModel.fromRow(row);
    // Decided on arrival: where the user is, and whether the app is in
    // front, is about now — not after the refresh below.
    final delivery = deliveryFor(
      notification,
      foreground:
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      currentLocation: _currentLocation(),
    );

    // The list and its badge first: the bell should be right whether or not
    // the OS lets us post anything.
    final refreshed = ref.read(notificationsProvider.notifier).refresh();
    // A chat message also moves the chat counters (Akun, the inbox). The
    // inbox has its own channel, but this row is the signal that reliably
    // arrives, so it is not left to that channel alone.
    if (notification.type == NotificationType.chatMessage) {
      unawaited(ref.read(chatThreadsProvider.notifier).refresh());
    }

    switch (delivery) {
      case NotificationDelivery.none:
        unawaited(refreshed);
      case NotificationDelivery.system:
        unawaited(refreshed);
        unawaited(
          LocalPush.instance.show(
            id: notification.id,
            title: notification.title.isEmpty
                ? 'pokepedia.id'
                : notification.title,
            body: notification.body,
            // Resolved now rather than on tap: the mapping belongs to this
            // build of the app, and the payload may outlive the row in the
            // tray.
            payload: appRouteForActionUrl(notification.actionUrl),
          ),
        );
      case NotificationDelivery.banner:
        // After the refresh: tapping the banner marks the row read, and
        // `markRead` only acts on rows the list already holds.
        try {
          await refreshed;
        } catch (_) {
          // Shown anyway — the tap still opens the screen.
        }
        ref.read(inAppBannerProvider.notifier).show(notification);
    }
  }

  void _openRoute(String route) {
    // The router, not a BuildContext: a tap can arrive with no screen of ours
    // in the foreground, including on a cold start.
    ref.read(notificationRouteOpenerProvider)(route);
  }

  /// Where the user is now, or null when the router can't say (not yet
  /// built).
  String? _currentLocation() {
    try {
      return appRouter.routerDelegate.currentConfiguration.uri.toString();
    } catch (_) {
      return null;
    }
  }

  void _teardown() {
    _channel?.unsubscribe();
    _channel = null;
    _taps?.cancel();
    _taps = null;
  }
}

/// How a new row reaches the user.
enum NotificationDelivery {
  /// Nothing to show — only the list and badges move.
  none,

  /// The in-app banner, over whatever screen is up.
  banner,

  /// An OS notification, for an app that is running but not in front.
  system,
}

/// Decides how [notification] is shown.
///
/// [foreground] is whether the app is the one on screen: an OS notification
/// over the app itself duplicates what a banner says better, and a banner
/// in a backgrounded app is seen by nobody. [currentLocation] is the
/// router's location.
///
/// A chat message for the conversation already open shows nothing: the
/// message is on screen as it arrives. Other screens are not live, so a row
/// about the order being looked at still gets its banner.
NotificationDelivery deliveryFor(
  NotificationModel notification, {
  required bool foreground,
  required String? currentLocation,
}) {
  // Already read means it was raised for something the user is looking at.
  if (notification.isRead) return NotificationDelivery.none;
  if (!foreground) return NotificationDelivery.system;

  if (notification.type == NotificationType.chatMessage &&
      currentLocation != null) {
    final route = appRouteForActionUrl(notification.actionUrl);
    final here = Uri.tryParse(currentLocation)?.path;
    if (route != null && Uri.tryParse(route)?.path == here) {
      return NotificationDelivery.none;
    }
  }
  return NotificationDelivery.banner;
}

/// Opens the screen a notification names. A provider so tests can see
/// where a tap went without a real router.
final notificationRouteOpenerProvider = Provider<void Function(String route)>(
  (ref) =>
      (route) => openAppRoute(appRouter, route),
);

final notificationPushProvider =
    NotifierProvider<NotificationPushNotifier, void>(
      NotificationPushNotifier.new,
    );
