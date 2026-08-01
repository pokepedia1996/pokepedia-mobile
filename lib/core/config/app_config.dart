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
  static const supabaseAnonKey = 'sb_publishable_hJI-p2MvaiuKQmOq8Tvxkw_vz-Zpgwi';

  /// The pokepedia-web deployment. Public — same status as [supabaseUrl] —
  /// used to hand off money-moving flows (checkout, payment, order actions)
  /// to the real site in the device's browser, since those routes only
  /// authenticate via browser cookies and the mobile app has no way to
  /// share a session with them.
  static const appUrl = 'https://pokepedia.id';
}
