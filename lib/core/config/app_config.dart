import 'dart:io' show Platform;

/// Supabase connection config. Points at the local Supabase stack
/// (`supabase start` in the `pokepedia-web` repo) by default.
///
/// Android emulators can't reach the host via `127.0.0.1` (that's the
/// emulator's own loopback) — `10.0.2.2` is the documented alias for the
/// host machine instead.
class AppConfig {
  const AppConfig._();

  static final supabaseUrl =
      Platform.isAndroid ? 'http://192.168.1.4:54321' : 'http://127.0.0.1:54321';
  static const supabaseAnonKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
}
