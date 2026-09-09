import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Raises OS notifications from inside the app.
///
/// Not remote push: the server's pipeline (`supabase/functions/push-notifications`)
/// speaks Web Push over VAPID, which only a browser can receive. What reaches
/// the app is the `notifications` row itself, over Realtime, and this turns
/// that row into a notification the phone shows. The consequence is the
/// honest one — it fires while the app is running, not after the OS has
/// stopped it. Delivering to a killed app needs FCM/APNs and a sender that
/// holds those credentials.
class LocalPush {
  LocalPush._();

  static final instance = LocalPush._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Emits the `action_url` of a notification the user tapped.
  final _taps = StreamController<String>.broadcast();
  Stream<String> get taps => _taps.stream;

  /// A tap that launched the app, held until someone asks for it.
  ///
  /// This cannot go out on [taps]: the payload is discovered inside [init],
  /// and every listener attaches *after* awaiting that same call, so a
  /// broadcast stream has nobody on it yet and drops the event on the floor.
  /// Tapping a notification that starts the app from cold then did nothing at
  /// all. Held here instead, and claimed once by [takeLaunchRoute].
  String? _launchRoute;

  bool _ready = false;
  bool _permitted = false;

  /// The channel the rows land in. Android groups and lets the user silence
  /// notifications per channel, so this is deliberately one channel for
  /// "things that happened on your account" rather than one per type.
  static const _channel = AndroidNotificationChannel(
    'account_activity',
    'Aktivitas akun',
    description: 'Pesanan, komplain, penawaran, dan pesan dari pembeli.',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Asked for on the first notification instead, so a fresh install
          // isn't met with a permission sheet before anything has happened.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _taps.add(payload);
      },
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    // A tap that started the app from cold: the payload is waiting here
    // rather than on the callback above.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.isNotEmpty) {
      _launchRoute = payload;
    }
  }

  /// The route a cold-start tap asked for, or null. Returns it once: a second
  /// caller — or a later sign-in rebuilding the listener — must not send the
  /// user back to the same screen again.
  String? takeLaunchRoute() {
    final route = _launchRoute;
    _launchRoute = null;
    return route;
  }

  /// Asks for permission the first time there is something to show. Returns
  /// false when the user has said no — nothing is posted in that case.
  Future<bool> _ensurePermission() async {
    if (_permitted) return true;
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      _permitted = await android?.requestNotificationsPermission() ?? false;
    } else if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      _permitted =
          await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    } else {
      _permitted = true;
    }
    return _permitted;
  }

  /// Shows one notification. [payload] travels back on [taps] when it is
  /// tapped — the app route to open, already resolved.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    if (!await _ensurePermission()) return;

    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            // The body is usually one line, but "pesanan #x dibatalkan
            // karena ..." is not; let it expand rather than ellipsing.
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (e) {
      // A notification that cannot be shown is not worth crashing over.
      if (kDebugMode) debugPrint('[push] show failed: $e');
    }
  }
}
