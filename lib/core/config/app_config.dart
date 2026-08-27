import 'dart:io' show Platform;

/// Supabase connection config. Points at the local Supabase stack
/// (`supabase start` in the `pokepedia-web` repo) by default.
///
/// Android emulators can't reach the host via `127.0.0.1` (that's the
/// emulator's own loopback) — `10.0.2.2` is the documented alias for the
/// host machine instead.
class AppConfig {
  const AppConfig._();

  static final supabaseUrl = 'https://ovbzifwfohqflfsgedsj.supabase.co';
  static const supabaseAnonKey =
      'sb_publishable_hJI-p2MvaiuKQmOq8Tvxkw_vz-Zpgwi';
  // static final supabaseUrl = 'http://192.168.1.5:54321';
  // static const supabaseAnonKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

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

  /// The pokepedia-web deployment. Public — same status as [supabaseUrl] —
  /// used to hand off money-moving flows (checkout, payment, order actions)
  /// to the real site in the device's browser, since those routes only
  /// authenticate via browser cookies and the mobile app has no way to
  /// share a session with them.
  static const appUrl = 'https://pokepedia.id';
}
