import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';
import 'package:pokepedia_mobile/core/network/session_cookie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A syntactically valid JWT — `Session.expiresAt` reads `exp` out of the
/// token itself, so a placeholder string would leave it null.
String _jwt({int exp = 1788409135, int padding = 0}) {
  String segment(Map<String, dynamic> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  final header = segment({'alg': 'ES256', 'typ': 'JWT'});
  final payload = segment({
    'sub': '11111111-1111-4111-8111-111111111111',
    'aud': 'authenticated',
    'role': 'authenticated',
    'exp': exp,
    if (padding > 0) 'pad': 'x' * padding,
  });
  return '$header.$payload.signature';
}

Session _session({String refreshToken = 'refresh-me', String? accessToken}) =>
    Session(
      accessToken: accessToken ?? _jwt(),
      tokenType: 'bearer',
      expiresIn: 3600,
      refreshToken: refreshToken,
      user: User(
        id: '11111111-1111-4111-8111-111111111111',
        appMetadata: const {'provider': 'email'},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-09-01T00:00:00Z',
        email: 'user1@test.com',
      ),
    );

Map<String, dynamic> _decode(String cookie) {
  final value = cookie.split('=').sublist(1).join('=');
  final payload = value.substring('base64-'.length);
  // The JS encoder emits unpadded base64url; Dart's decoder wants padding.
  final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
  return jsonDecode(utf8.decode(base64Url.decode(padded)))
      as Map<String, dynamic>;
}

/// `/api/scan` (and the wallet and dispatch routes) authenticate from the
/// `@supabase/ssr` cookie and never read `Authorization`, so a native client
/// has to present its session in that shape too. The format is the server's,
/// not ours — a name or an encoding that drifts is a silent 401 that the app
/// then reports as an expired session.
void main() {
  group('cookie name', () {
    test('is the storageKey supabase-js derives from the host', () {
      expect(
        PokepediaApi.sessionCookieName('https://abcdefghijklmnop.supabase.co'),
        'sb-abcdefghijklmnop-auth-token',
      );
      // A local `supabase start` stack, which is what dev builds point at.
      expect(
        PokepediaApi.sessionCookieName('http://127.0.0.1:54321'),
        'sb-127-auth-token',
      );
    });

    /// The production 401. This build dials `auth.pokepedia.id`, a custom
    /// domain in front of the project, so naming the cookie after our own URL
    /// produced `sb-auth-auth-token` — while pokepedia-web reads
    /// `sb-tlauakxyrxpwnwgdywum-auth-token`, the name its
    /// `docs/security/firewall.md` states outright. The token's `iss` is the
    /// project both sides share, so that is what names the cookie.
    test('follows the token issuer, not the host this build dials', () {
      // What the old rule produced from the production build's SUPABASE_URL.
      expect(
        PokepediaApi.sessionCookieName('https://auth.pokepedia.id'),
        'sb-auth-auth-token',
      );

      // What the server actually reads, and what the app now sends.
      expect(
        supabaseAuthCookieNameForToken(
          unsignedJwt({
            'iss': 'https://tlauakxyrxpwnwgdywum.supabase.co/auth/v1',
          }),
        ),
        'sb-tlauakxyrxpwnwgdywum-auth-token',
      );
    });

    test('an unreadable token falls back rather than sending nothing', () {
      for (final token in ['', 'nope', 'a.b', 'a.###.c']) {
        expect(
          supabaseAuthCookieNameForToken(token),
          supabaseAuthCookieName,
          reason: 'token: $token',
        );
      }
    });
  });

  group('cookie value', () {
    test('is base64url of the session JSON, as the browser writes it', () {
      final cookie = PokepediaApi.buildSessionCookie(
        'sb-127-auth-token',
        _session(),
        'fresh.access.token',
      )!;
      expect(cookie, startsWith('sb-127-auth-token=base64-'));
      // Unpadded, matching `stringToBase64URL`.
      expect(cookie, isNot(contains('==')));

      final decoded = _decode(cookie);
      expect(decoded['access_token'], 'fresh.access.token');
      expect(decoded['token_type'], 'bearer');
      expect(decoded['expires_at'], 1788409135);
      expect((decoded['user'] as Map)['email'], 'user1@test.com');
    });

    test('carries the token being sent, not a stale one from the store', () {
      final cookie = PokepediaApi.buildSessionCookie(
        'sb-127-auth-token',
        _session(),
        'refreshed.token',
      )!;
      expect(_decode(cookie)['access_token'], 'refreshed.token');
    });

    test('never carries the refresh token', () {
      // A server that found the access token expired would refresh it,
      // rotating the refresh token where the app cannot see the replacement
      // — ending the very session it was trying to use.
      final cookie = PokepediaApi.buildSessionCookie(
        'sb-127-auth-token',
        _session(refreshToken: 'do-not-send-me'),
        'fresh.access.token',
      )!;
      expect(cookie, isNot(contains('do-not-send-me')));
      expect(_decode(cookie)['refresh_token'], '');
    });
  });

  group('chunking', () {
    test('splits past the size @supabase/ssr reads back', () {
      final long = _jwt(padding: 5000);
      final cookie = PokepediaApi.buildSessionCookie(
        'sb-127-auth-token',
        _session(accessToken: long),
        long,
      )!;

      expect(cookie, contains('sb-127-auth-token.0='));
      expect(cookie, contains('sb-127-auth-token.1='));
      // The reader concatenates the bare name *and* the chunks, so sending
      // both would double the value.
      expect(cookie, isNot(contains('sb-127-auth-token=')));
      for (final part in cookie.split('; ')) {
        expect(part.split('=')[1].length, lessThanOrEqualTo(3180));
      }
    });
  });
}

/// An unsigned JWT carrying [claims]. The signature is never checked when
/// choosing a cookie name, and forging one would only name a cookie the
/// server does not read.
String unsignedJwt(Map<String, dynamic> claims) {
  String seg(Map<String, dynamic> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${seg({'alg': 'ES256', 'typ': 'JWT'})}.${seg(claims)}.sig';
}
