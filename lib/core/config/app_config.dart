import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Supabase connection config. Points at the local Supabase stack
/// (`supabase start` in the `pokepedia-web` repo) by default.
///
/// Android emulators can't reach the host via `127.0.0.1` (that's the
/// emulator's own loopback) — `10.0.2.2` is the documented alias for the
/// host machine instead.
class AppConfig {
  const AppConfig._();

  /// Which Supabase issues the session.
  ///
  /// This has to match whatever [appUrl] validates against, or every call to
  /// a web route fails with 401: the server hands the app's token to *its*
  /// Supabase, and a token signed by a different project is simply invalid
  /// there. So the two default together — debug to the local stack, release
  /// to the cloud — and are overridden together.
  ///
  /// ```
  /// flutter run \
  ///   --dart-define=SUPABASE_URL=http://192.168.1.5:54321 \
  ///   --dart-define=SUPABASE_ANON_KEY=sb_publishable_... \
  ///   --dart-define=APP_URL=http://192.168.1.5:3000
  /// ```
  static final supabaseUrl =
      const String.fromEnvironment('SUPABASE_URL').isNotEmpty
      ? const String.fromEnvironment('SUPABASE_URL')
      : (kDebugMode
            ? (Platform.isAndroid
                  ? 'http://192.168.0.120:54321'
                  : 'http://127.0.0.1:54321')
            : 'http://192.168.0.120:54321');

  static final supabaseAnonKey =
      const String.fromEnvironment('SUPABASE_ANON_KEY').isNotEmpty
      ? const String.fromEnvironment('SUPABASE_ANON_KEY')
      : (kDebugMode
            ? 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
            : 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH');

  /// Google's **web** OAuth client id — the one configured in Supabase under
  /// Authentication > Providers > Google. Native sign-in sends it as
  /// `serverClientId`, and Supabase verifies the ID token's audience against
  /// it, so the two must be the same value.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// Google's **iOS** OAuth client id. Android identifies the app by package
  /// name and signing fingerprint instead, so it needs no id here.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// The pokepedia-web deployment the app calls for the few routes that need
  /// a server secret (checkout, shipping rates, the courier catalogue).
  ///
  /// Debug builds point at a local `next dev` server, release builds at
  /// production. Either can be overridden explicitly:
  ///
  /// ```
  /// flutter run --dart-define=APP_URL=http://192.168.1.5:3000    # LAN device
  /// flutter run --dart-define=APP_URL=https://www.pokepedia.id   # force prod
  /// ```
  ///
  /// The `www.` on the production host matters: the apex answers every
  /// request with a 308 to it, and Dart's `HttpClient` only auto-follows
  /// redirects for GET and HEAD. A POST to the apex therefore *returns* the
  /// redirect body instead of the route's.
  static final appUrl = const String.fromEnvironment('APP_URL').isNotEmpty
      ? const String.fromEnvironment('APP_URL')
      : (kDebugMode ? _localAppUrl : 'https://www.pokepedia.id');

  /// Where `next dev` is, as seen *from the device*.
  ///
  /// `localhost` would be the phone or emulator itself, not the machine
  /// running the server. `10.0.2.2` is Android's alias for the host; the iOS
  /// simulator shares the Mac's loopback so `localhost` is right there.
  ///
  /// A physical Android device is on neither — it needs the machine's LAN
  /// address, which only the developer knows, so pass `APP_URL` for that.
  static final _localAppUrl = Platform.isAndroid
      ? 'http://10.0.2.2:3000'
      : 'http://localhost:3000';

  /// True when [appUrl] points at something other than the real site — a
  /// local dev server, or a preview deployment.
  static bool get isLocalApi => !appUrl.contains('pokepedia.id');
}
