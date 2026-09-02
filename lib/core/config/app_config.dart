import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Every URL and key the app is pointed at, read from `env.json`.
///
/// Pass it on every run and build:
///
/// ```
/// flutter run   --dart-define-from-file=env.json
/// flutter build apk --dart-define-from-file=env.json
/// ```
///
/// `env.json` is gitignored because it holds keys; `env.example.json` is the
/// checked-in list of what belongs in it.
///
/// ## Why these are configuration and not constants
///
/// [supabaseUrl] and [appUrl] are two halves of one decision. The app signs in
/// against Supabase and sends that token to a pokepedia-web route; the route
/// hands it to *its* Supabase to validate. A token signed by a different
/// project is simply invalid there, so pointing the two at different stacks
/// makes every authenticated route fail with a bare 401 that looks like a
/// session bug. They move together or not at all.
///
/// Host names also depend on where the app is running, which no default can
/// know: `127.0.0.1` is the phone itself on a device, the emulator's own
/// loopback on Android, and the Mac on an iOS simulator. A physical device
/// needs the machine's LAN address. That is exactly the kind of value that
/// belongs in a file the developer owns rather than in source.
class AppConfig {
  const AppConfig._();

  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _appUrl = String.fromEnvironment('APP_URL');

  /// Which Supabase issues the session. See the class doc — this and [appUrl]
  /// have to name the same stack.
  static final supabaseUrl = _supabaseUrl.isNotEmpty
      ? _supabaseUrl
      : _missing('SUPABASE_URL', _localSupabaseUrl);

  static final supabaseAnonKey = _supabaseAnonKey.isNotEmpty
      ? _supabaseAnonKey
      : _missing('SUPABASE_ANON_KEY', '');

  /// The pokepedia-web deployment the app calls for the routes that need a
  /// server secret — checkout, shipping rates, the courier catalogue, scan.
  ///
  /// The `www.` on production matters: the apex answers every request with a
  /// 308 to it, and Dart's `HttpClient` only auto-follows redirects for GET
  /// and HEAD. A POST to the apex therefore *returns* the redirect body
  /// instead of the route's, which reads as a malformed response rather than
  /// as a redirect.
  static final appUrl = _appUrl.isNotEmpty
      ? _appUrl
      : _missing('APP_URL', _localAppUrl);

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

  /// True when [appUrl] points at something other than the real site — a
  /// local dev server, or a preview deployment.
  static bool get isLocalApi => !appUrl.contains('pokepedia.id');

  /// The local stack as seen *from the device*, used only as a debug
  /// fallback. `10.0.2.2` is Android's documented alias for the host machine;
  /// the iOS simulator shares the Mac's loopback.
  ///
  /// A physical device is on neither and needs the machine's LAN address —
  /// which is why `env.json` exists.
  static String get _localSupabaseUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:54321' : 'http://127.0.0.1:54321';

  static String get _localAppUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';

  /// Handles a key that `env.json` didn't supply.
  ///
  /// In debug it falls back to the local stack and says so once, because
  /// forgetting `--dart-define-from-file` is a normal mistake with an obvious
  /// fix. In release it throws: a shipped build with no configured backend
  /// cannot work, and failing at startup is far cheaper to diagnose than
  /// every network call failing later for reasons that look unrelated.
  static String _missing(String key, String fallback) {
    if (kReleaseMode) {
      throw StateError(
        '$key is not set. Build with --dart-define-from-file=env.json.',
      );
    }
    debugPrint(
      '[config] $key not set; falling back to $fallback. '
      'Pass --dart-define-from-file=env.json to override.',
    );
    return fallback;
  }
}
