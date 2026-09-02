import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/router/app_router.dart';
import '../../../core/notifications/local_push.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/models/notification_model.dart';
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
/// What this is not: remote push. The row has to reach a running app, so a
/// notification raised while the process is dead is not delivered — see
/// [LocalPush] for what that would take.
class NotificationPushNotifier extends Notifier<void> {
  RealtimeChannel? _channel;
  StreamSubscription<String>? _taps;

  @override
  void build() {
    final user = ref.watch(authProvider).valueOrNull;

    ref.onDispose(_teardown);
    if (user == null) {
      _teardown();
      return;
    }

    unawaited(_start(user.id));
  }

  Future<void> _start(String userId) async {
    await LocalPush.instance.init();
    _taps ??= LocalPush.instance.taps.listen(_openRoute);

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
          callback: (payload) => _onInserted(payload.newRecord),
        )
        .subscribe();
  }

  void _onInserted(Map<String, dynamic> row) {
    final notification = NotificationModel.fromRow(row);

    // The list and its badge first: the bell should be right whether or not
    // the OS lets us post anything.
    ref.read(notificationsProvider.notifier).refresh();

    // Already read means it was raised for something the user is looking at.
    if (notification.isRead) return;

    unawaited(
      LocalPush.instance.show(
        id: notification.id,
        title: notification.title.isEmpty ? 'pokepedia.id' : notification.title,
        body: notification.body,
        // Resolved now rather than on tap: the mapping belongs to this build
        // of the app, and the payload may outlive the row in the tray.
        payload: appRouteForActionUrl(notification.actionUrl),
      ),
    );
  }

  void _openRoute(String route) {
    if (route.isEmpty) return;
    // The router, not a BuildContext: a tap can arrive with no screen of ours
    // in the foreground, including on a cold start.
    appRouter.push(route);
  }

  void _teardown() {
    _channel?.unsubscribe();
    _channel = null;
    _taps?.cancel();
    _taps = null;
  }
}

final notificationPushProvider =
    NotifierProvider<NotificationPushNotifier, void>(
      NotificationPushNotifier.new,
    );
