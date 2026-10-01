import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_provider.dart';

/// The path the emailed links land on, claimed by the Android intent filter
/// and the iOS associated domain. Anything else is left alone — the OS only
/// hands us this one, but a stray link should still fall through quietly.
const _confirmPath = '/auth/confirm';

/// The hosts whose links this app is allowed to redeem. Both are claimed,
/// because App Links do not follow redirects and the apex is what
/// `NEXT_PUBLIC_APP_URL` falls back to. Checked here as well as in the
/// manifest so a link arriving by any other route is still not trusted.
const _hosts = {'www.pokepedia.id', 'pokepedia.id'};

/// What `type=` in the link maps to. Mirrors the set `app/auth/confirm/
/// route.ts` accepts, so a link the website would honour is one the app
/// honours too.
const _types = <String, OtpType>{
  'signup': OtpType.signup,
  'recovery': OtpType.recovery,
  'invite': OtpType.invite,
  'email': OtpType.email,
  'magiclink': OtpType.magiclink,
};

/// Redeems the `token_hash` on an emailed confirmation or recovery link.
///
/// The app is the right place to do this rather than the website: signup
/// runs under PKCE, so the code verifier lives on *this device* and only
/// this client can complete the exchange. That is the whole reason the links
/// are App Links — the website's `/auth/confirm` stays the fallback for
/// someone without the app installed, and handles the signups that started
/// in a browser.
class AuthLinkHandler {
  AuthLinkHandler(this._client, {AppLinks? links})
    : _links = links ?? AppLinks();

  final SupabaseClient _client;
  final AppLinks _links;
  StreamSubscription<Uri>? _sub;

  /// Starts listening. Covers the cold-start case too: `uriLinkStream` only
  /// carries links that arrive while the app is running, so a tap that
  /// launched the app would otherwise be dropped.
  Future<void> start() async {
    _sub ??= _links.uriLinkStream.listen(
      handle,
      onError: (Object e) => debugPrint('[authlink] stream error: $e'),
    );
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) await handle(initial);
    } catch (e) {
      debugPrint('[authlink] initial link failed: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Returns the type that was redeemed, or null when the link was not one
  /// of ours or could not be completed. Visible for testing.
  @visibleForTesting
  Future<OtpType?> handle(Uri uri) async {
    if (!_hosts.contains(uri.host)) return null;
    if (!uri.path.startsWith(_confirmPath)) return null;

    final hash = uri.queryParameters['token_hash'];
    final type = _types[uri.queryParameters['type']];
    if (hash == null || hash.isEmpty || type == null) return null;

    try {
      await _client.auth.verifyOTP(tokenHash: hash, type: type);
      return type;
    } on AuthException catch (e) {
      // A link that was already used, or expired. Nothing to recover here:
      // the session state is unchanged and the user stays where they were.
      debugPrint('[authlink] verify failed: ${e.message}');
      return null;
    }
  }
}

final authLinkHandlerProvider = Provider<AuthLinkHandler>((ref) {
  final handler = AuthLinkHandler(ref.watch(supabaseClientProvider));
  ref.onDispose(handler.dispose);
  return handler;
});
