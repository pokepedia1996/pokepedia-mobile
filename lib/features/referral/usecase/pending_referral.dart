import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';

/// A referral code's shape: 1–5 letters or digits from the referrer's
/// username, then three digits (`SATOS728`), as `_referral_code_check`
/// issues them.
final referralCodeShape = RegExp(r'^[A-Z0-9]{1,5}[0-9]{3}$');

/// A referral code from a tapped invite link (`www.pokepedia.id/r/<code>`),
/// held until onboarding's code field can take it.
///
/// Kept on the device, not just in memory: a friend who taps the link signs
/// up, leaves to confirm their email and comes back through the emailed
/// link, which starts the app afresh. Read once in `main` like `IntroFlag`,
/// so the field is filled the moment onboarding opens.
class PendingReferral {
  PendingReferral._();

  static const _key = 'pokepedia.pending-referral.v1';

  /// The hosts an invite link may come from. The apex is listed for a link
  /// reaching the app by any other route, though only `www` is an App Link.
  static const _hosts = {'www.pokepedia.id', 'pokepedia.id'};

  /// The app's own scheme, `id.pokepedia.app://r/<code>`: it opens the app
  /// with no domain association, which is how an invite is tried locally
  /// (`xcrun simctl openurl booted id.pokepedia.app://r/USER1266`).
  static const _scheme = 'id.pokepedia.app';

  /// The website this build talks to (`APP_URL` in env.json: localhost,
  /// ngrok, staging), so its `/r/<code>` links count too.
  static String? get _appHost {
    try {
      final host = Uri.parse(AppConfig.appUrl).host;
      return host.isEmpty ? null : host;
    } catch (_) {
      return null;
    }
  }

  static final code = ValueNotifier<String?>(null);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      code.value = prefs.getString(_key);
    } catch (_) {}
  }

  static Future<void> save(String value) async {
    code.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value);
    } catch (_) {}
  }

  /// Once the code was used, or turned out to be no use to this account.
  static Future<void> clear() async {
    code.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  /// The code in an invite link, or null when [uri] is not one.
  static String? codeFromLink(Uri uri) {
    final String raw;
    if (uri.scheme == _scheme && uri.host == 'r') {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length != 1) return null;
      raw = segments.single;
    } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        (_hosts.contains(uri.host) || uri.host == _appHost)) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length != 2 || segments.first != 'r') return null;
      raw = segments.last;
    } else {
      return null;
    }
    final value = raw.trim().toUpperCase();
    return referralCodeShape.hasMatch(value) ? value : null;
  }
}
