import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import '../config/app_config.dart';

/// One cookie the web app expects to find.
class SessionCookie {
  const SessionCookie(this.name, this.value);

  final String name;
  final String value;
}

/// `sb-<project-ref>-auth-token` — the storage key supabase-js derives from
/// the project URL, and the name `@supabase/ssr` reads on the server.
///
/// Both sides must derive it from the *same* URL. Against the cloud project
/// they do. Against a local stack they don't: the app reaches it at
/// `10.0.2.2` and the server at `127.0.0.1`, which yield `sb-10-` and
/// `sb-127-`. That is why the transport prefers the bearer header locally —
/// see `PokepediaApi._retrying`.
final supabaseAuthCookieName =
    'sb-${Uri.parse(AppConfig.supabaseUrl).host.split('.').first}-auth-token';

/// `MAX_CHUNK_SIZE` in `@supabase/ssr`.
const maxCookieChunk = 3180;

/// The `@supabase/ssr` session cookies for [session].
///
/// This is what lets the app be recognised by pokepedia.id without a second
/// login: the same cookie a browser would hold, built from the session the
/// app already has. Used both for API calls and to seed the WebView, so the
/// two can never drift apart.
///
/// Format, taken from the installed `@supabase/ssr`: `base64-` followed by
/// the **unpadded** base64url of the session JSON, split into `.0`, `.1`, …
/// once past [maxCookieChunk]. The value is base64url plus that prefix, so
/// every character is cookie-safe and the split is a plain slice — the
/// package chunks on the URL-encoded form, which here is identical.
List<SessionCookie> buildSessionCookies(Session session) {
  final payload = jsonEncode({
    'access_token': session.accessToken,
    'token_type': session.tokenType,
    'expires_in': session.expiresIn,
    'expires_at': session.expiresAt,
    'refresh_token': session.refreshToken,
    'user': session.user.toJson(),
  });
  // Unpadded, matching the package's `stringToBase64URL`; a trailing `=`
  // would have to be escaped in a cookie.
  final encoded = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  final value = 'base64-$encoded';

  if (value.length <= maxCookieChunk) {
    return [SessionCookie(supabaseAuthCookieName, value)];
  }

  final cookies = <SessionCookie>[];
  for (var i = 0, chunk = 0; i < value.length; i += maxCookieChunk, chunk++) {
    final end = (i + maxCookieChunk).clamp(0, value.length);
    cookies.add(
      SessionCookie('$supabaseAuthCookieName.$chunk', value.substring(i, end)),
    );
  }
  return cookies;
}

/// The same cookies as a `Cookie:` header value.
String? sessionCookieHeader(Session? session) {
  if (session == null) return null;
  return buildSessionCookies(
    session,
  ).map((c) => '${c.name}=${c.value}').join('; ');
}
