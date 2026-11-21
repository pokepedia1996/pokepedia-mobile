import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/router/routes.dart';

/// Whether this device has already left the first-launch intro.
///
/// The router's redirect is synchronous, so the flag is read once in `main`
/// before `runApp` and kept in a [ValueNotifier]. It starts `true`: anything
/// that never calls [load] (tests, previews) must not be diverted to the
/// intro. A real launch sets it from storage, where unset means not seen.
class IntroFlag {
  IntroFlag._();

  static const _key = 'pokepedia.intro-seen.v1';

  static final done = ValueNotifier<bool>(true);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      done.value = prefs.getBool(_key) ?? false;
    } catch (_) {
      // Storage unreadable: skip the intro rather than trap anyone in it.
      done.value = true;
    }
  }

  /// Called when the user leaves the intro by any door (sign-in, "Masuk",
  /// email signup, "Lihat-lihat dulu"). Closing the app mid-intro leaves it
  /// unset on purpose, so the intro comes back until it is finished.
  static Future<void> markDone() async {
    done.value = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {}
  }
}

/// Where the router sends [location] for the intro, or null to leave it.
///
/// First launch, signed out: Beranda gives way to the intro. Only Beranda
/// does, so deep links (email confirm, reset password, a card link) open
/// where they point. A signed-in user never sees the intro.
String? introRedirect({
  required bool loggedIn,
  required bool introDone,
  required String location,
}) {
  if (!loggedIn && !introDone && location == Routes.home) {
    return Routes.welcome;
  }
  if (loggedIn && location == Routes.welcome) return Routes.home;
  return null;
}
