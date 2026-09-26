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
/// Derived from the URL this build was pointed at, which is only the right
/// answer when the server was pointed at the same one. See
/// [supabaseAuthCookieNameFor], which is what actually names the cookie.
final supabaseAuthCookieName = _cookieNameForUrl(AppConfig.supabaseUrl);

String _cookieNameForUrl(String url) =>
    'sb-${Uri.parse(url).host.split('.').first}-auth-token';

/// The cookie name for [session], taken from the token's own `iss`.
///
/// Both sides have to derive this name from the same URL, and they were not.
/// The app reaches Supabase through `auth.pokepedia.id`, a custom domain in
/// front of the project, so it named the cookie `sb-auth-auth-token`. The web
/// app is configured with the project URL, so `@supabase/ssr` looked for
/// `sb-<project-ref>-auth-token`, found nothing, and treated a perfectly good
/// session as anonymous — every authenticated route answering 401 with a
/// valid bearer token sitting unread in the headers, because the server's
/// client reads cookies and never looks at that header.
///
/// The token settles it: `iss` is the project that issued it, and that is
/// necessarily the project the server validates against — a token signed by
/// any other one could not be verified there at all. Deriving from `iss`
/// rather than from our own URL therefore agrees with the server whatever
/// hostname this build happens to dial.
///
/// This also closes the local-stack gap the transport works around by
/// preferring the bearer header: `iss` is the same string whether the app
/// reached the stack at `10.0.2.2` and the server at `127.0.0.1`.
///
/// Falls back to [supabaseAuthCookieName] when the token carries no readable
/// `iss` — a malformed name is no worse than the one we had.
String supabaseAuthCookieNameFor(Session session) =>
    supabaseAuthCookieNameForToken(session.accessToken);

/// As [supabaseAuthCookieNameFor], for the token actually being sent — which
/// is not always the one on [Session], since the transport refreshes first.
String supabaseAuthCookieNameForToken(String accessToken) {
  final issuer = _issuerOf(accessToken);
  if (issuer == null) return supabaseAuthCookieName;
  return _cookieNameForUrl(issuer);
}

/// The `iss` claim of a JWT, or null if it can't be read. Unverified on
/// purpose: the signature is the server's business, and this only picks a
/// cookie name — a forged `iss` names a cookie the server won't read.
String? _issuerOf(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    // base64url without padding, which `base64Url.decode` requires.
    final payload = parts[1];
    final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    final claims = jsonDecode(utf8.decode(base64Url.decode(padded)));
    if (claims is! Map) return null;
    final issuer = claims['iss'];
    if (issuer is! String || issuer.isEmpty) return null;
    // `https://<ref>.supabase.co/auth/v1` — only the host is wanted.
    if (Uri.parse(issuer).host.isEmpty) return null;
    return issuer;
  } catch (_) {
    return null;
  }
}

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
  final name = supabaseAuthCookieNameFor(session);
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
    return [SessionCookie(name, value)];
  }

  final cookies = <SessionCookie>[];
  for (var i = 0, chunk = 0; i < value.length; i += maxCookieChunk, chunk++) {
    final end = (i + maxCookieChunk).clamp(0, value.length);
    cookies.add(SessionCookie('$name.$chunk', value.substring(i, end)));
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
