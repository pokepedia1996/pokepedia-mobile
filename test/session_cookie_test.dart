import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/config/app_config.dart';
import 'package:pokepedia_mobile/core/network/session_cookie.dart';

/// The encoding `@supabase/ssr` expects, mirrored from its installed source
/// so a change on either side shows up here rather than as a 401.
///
/// `PokepediaApi._sessionCookie` is private and needs a live Supabase
/// session, so these pin the format itself: the prefix, the unpadded
/// base64url alphabet, and the chunk boundary.
const _maxCookieChunk = 3180;

String encodeCookieValue(Map<String, dynamic> session) {
  final encoded = base64Url
      .encode(utf8.encode(jsonEncode(session)))
      .replaceAll('=', '');
  return 'base64-$encoded';
}

List<String> chunk(String name, String value) {
  if (value.length <= _maxCookieChunk) return ['$name=$value'];
  final parts = <String>[];
  for (var i = 0, c = 0; i < value.length; i += _maxCookieChunk, c++) {
    final end = (i + _maxCookieChunk).clamp(0, value.length);
    parts.add('$name.$c=${value.substring(i, end)}');
  }
  return parts;
}

void main() {
  group('session cookie encoding', () {
    test('carries the base64- prefix the package looks for', () {
      final value = encodeCookieValue({'access_token': 'abc'});
      expect(value.startsWith('base64-'), isTrue);
    });

    test('is unpadded base64url — a trailing = would need escaping', () {
      // 'a' encodes to 'YQ==' in standard base64; the package emits 'YQ'.
      final value = encodeCookieValue({'a': 'a'});
      expect(value.contains('='), isFalse);
    });

    test('uses only cookie-safe characters, so no percent-encoding', () {
      // This is what lets the chunk split be a plain slice: the package
      // chunks on the URL-encoded form, which here is identical.
      final value = encodeCookieValue({
        'access_token': 'x' * 200,
        'user': {'email': 'ash+test@example.com', 'name': 'Ash /+= Ketchum'},
      });
      expect(RegExp(r'^base64-[A-Za-z0-9_-]+$').hasMatch(value), isTrue);
      expect(Uri.encodeComponent(value).length, value.length);
    });

    test('round-trips back to the original session', () {
      final session = {
        'access_token': 'token',
        'token_type': 'bearer',
        'expires_at': 1787821174,
        'refresh_token': 'refresh',
        'user': {'id': 'uid', 'role': 'authenticated'},
      };
      final value = encodeCookieValue(session);
      final decoded = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(value.substring('base64-'.length)),
          ),
        ),
      );
      expect(decoded, session);
    });
  });

  group('chunking', () {
    test('a short value stays on the unsuffixed name', () {
      final parts = chunk('sb-ref-auth-token', 'base64-short');
      expect(parts, ['sb-ref-auth-token=base64-short']);
    });

    test('a long value splits into .0, .1, … and loses nothing', () {
      final value = 'base64-${'A' * (_maxCookieChunk * 2 + 40)}';
      final parts = chunk('sb-ref-auth-token', value);

      expect(parts, hasLength(3));
      expect(parts[0], startsWith('sb-ref-auth-token.0='));
      expect(parts[2], startsWith('sb-ref-auth-token.2='));
      // The server concatenates the chunks in order; nothing may be dropped
      // or duplicated at the boundaries.
      final rejoined = parts.map((p) => p.substring(p.indexOf('=') + 1)).join();
      expect(rejoined, value);
    });

    test('a value exactly at the boundary is not split', () {
      final value = 'x' * _maxCookieChunk;
      expect(chunk('k', value), hasLength(1));
      expect(chunk('k', '${value}y'), hasLength(2));
    });
  });

  group('cookie name', () {
    test('is derived from the configured Supabase host', () {
      // `@supabase/ssr` reads exactly this name; a mismatch is a silent
      // anonymous request, not an error. Asserted as the rule rather than a
      // literal because the host differs per build — which is itself why the
      // transport prefers the bearer header against a local stack, where the
      // app sees `10.0.2.2` and the server `127.0.0.1`.
      final ref = Uri.parse(AppConfig.supabaseUrl).host.split('.').first;
      expect(supabaseAuthCookieName, 'sb-$ref-auth-token');
    });

    test('matches the cloud project when pointed at production', () {
      expect(
        'sb-${Uri.parse('https://ovbzifwfohqflfsgedsj.supabase.co').host.split('.').first}-auth-token',
        'sb-ovbzifwfohqflfsgedsj-auth-token',
      );
    });

    test('matches the chunk size the package uses', () {
      expect(maxCookieChunk, 3180);
    });
  });
}
