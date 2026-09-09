import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Authenticated transport for the handful of pokepedia.id routes a mobile
/// client legitimately needs.
///
/// The web's route handlers all authenticate through `getRequestAuth`
/// (`lib/supabase/request.ts`), which reads `Authorization: Bearer <token>`
/// before falling back to the browser's `@supabase/ssr` cookie — it was
/// written for exactly this case ("Native clients hold a Supabase access
/// token, not the chunked cookie"). So the app authenticates with the same
/// Supabase session it already holds, and the Biteship and Xendit secrets
/// never leave the server.
class PokepediaApi {
  PokepediaApi(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  static const _timeout = Duration(seconds: 30);

  /// Enough for an apex-to-`www` hop and one more; past that the server is
  /// looping and following further only hides it.
  static const _maxRedirects = 3;

  /// How far ahead of expiry to refresh, matching the SDK's own timer.
  static const _refreshMargin = Duration(seconds: 30);

  /// The value of the `x-pokepedia-client` header that pokepedia.id's
  /// firewall rule looks for.
  ///
  /// Held in Supabase Vault rather than compiled into the app, so it can be
  /// rotated without a release; fetched once per app run and re-fetched if
  /// the edge ever challenges us again, which is what a rotation looks like
  /// from here.
  String? _bypassKey;

  /// In flight, so several parallel calls share one fetch rather than each
  /// spending its own round trip on the same secret.
  Future<String?>? _bypassKeyInFlight;

  /// The header value, fetched once per run and reused.
  ///
  /// Called *before* the first request rather than only after a challenge:
  /// waiting for the edge to turn us away means every app run burns one
  /// failed checkout before the header is ever sent, and a request that
  /// fails for an unrelated reason in that window looks like a WAF problem.
  Future<String?> _ensureBypassKey() {
    // A local dev server has no firewall to satisfy, and the Edge Function
    // this fetches from is a round trip that would just fail closed.
    if (AppConfig.isLocalApi) return Future.value(null);

    final cached = _bypassKey;
    if (cached != null) return Future.value(cached);
    return _bypassKeyInFlight ??= _fetchBypassKey().whenComplete(() {
      _bypassKeyInFlight = null;
    });
  }

  Future<String?> _fetchBypassKey() async {
    try {
      final response = await _client.functions.invoke('client-config');
      final data = response.data;
      if (data is Map && data['bypassKey'] is String) {
        _bypassKey = data['bypassKey'] as String;
        return _bypassKey;
      }
    } catch (_) {
      // Not fatal: without the header the request is challenged, and the
      // caller already handles that path.
    }
    return null;
  }

  Future<Map<String, dynamic>> get(String path) =>
      _retrying(() => _send('GET', path, null));

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _retrying(() => _send('POST', path, body));

  /// `multipart/form-data` POST, for the routes that take a file rather than
  /// JSON — today only `/api/scan`, which reads its image out of a `FormData`.
  ///
  /// Goes through the same [_retrying] ladder as [post], so a scan gets the
  /// same one-refresh-one-retry treatment on 401 and the same bypass-key
  /// recovery on a WAF challenge. [timeout] is separate from the default
  /// because recognition is a genuinely long request: `/api/scan` declares
  /// `maxDuration = 60` and budgets 50s internally, so a 30s client timeout
  /// would abandon scans the server was still going to answer.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    Map<String, String> fields = const {},
    List<ApiMultipartFile> files = const [],
    Duration? timeout,
  }) => _retrying(
    () => _send(
      'POST',
      path,
      null,
      multipart: _buildMultipart(fields, files),
      timeout: timeout,
    ),
  );

  /// Encodes [fields] and [files] into one RFC 7578 body.
  ///
  /// Built whole in memory rather than streamed: the only caller sends a
  /// single card photo already capped well under `/api/scan`'s own 4.5 MB
  /// limit, and a streamed body would have to be rebuilt from scratch for
  /// [_retrying]'s second attempt anyway.
  _MultipartBody _buildMultipart(
    Map<String, String> fields,
    List<ApiMultipartFile> files,
  ) {
    // Long and random-ish so it cannot occur inside a JPEG payload.
    final boundary =
        '----pokepediaMobile'
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final buffer = BytesBuilder(copy: false);

    void writeLine(String value) => buffer.add(utf8.encode('$value\r\n'));

    for (final entry in fields.entries) {
      writeLine('--$boundary');
      writeLine('Content-Disposition: form-data; name="${entry.key}"');
      writeLine('');
      writeLine(entry.value);
    }
    for (final file in files) {
      writeLine('--$boundary');
      writeLine(
        'Content-Disposition: form-data; name="${file.field}"; '
        'filename="${file.filename}"',
      );
      writeLine('Content-Type: ${file.contentType}');
      writeLine('');
      buffer.add(file.bytes);
      buffer.add(utf8.encode('\r\n'));
    }
    writeLine('--$boundary--');

    return _MultipartBody(boundary: boundary, bytes: buffer.takeBytes());
  }

  /// Runs a request, escalating through the recoveries that exist.
  ///
  /// A 401 buys exactly one token refresh and one retry. `getRequestAuth`
  /// collapses every auth failure into 401 — including a transient GoTrue
  /// outage — so treating a single one as "session dead, clear credentials"
  /// would sign out the entire user base during a brief provider incident.
  /// This is §7.2 of the bearer-auth handoff, and the reason the caller
  /// never sees the first failure.
  Future<Map<String, dynamic>> _retrying(
    Future<Map<String, dynamic>> Function() send,
  ) async {
    try {
      return await send();
    } on ApiAuthException {
      // One refresh, one retry — the sequence the 401 diagnosis prescribes.
      // A 401 alone is not proof the session is dead: `getRequestAuth`
      // collapses every auth failure into it, a token can expire in flight,
      // and a transient GoTrue outage looks identical.
      try {
        await _auth.refreshSession();
      } on AuthException {
        // Refresh itself was refused. That *is* the "your refresh token is
        // gone" signal, and it is the only thing here worth signing out for.
        throw const ApiSessionExpiredException();
      }
      try {
        return await send();
      } on ApiAuthException {
        // Refused again on a token minted seconds ago. The session is fine —
        // it was just refreshed — so this is the server not accepting it:
        // a route that authenticates from the browser cookie and never reads
        // `Authorization`, a token issued by a different Supabase project,
        // or a clock far enough out for `exp` to look stale. Sending the user
        // to the login screen for any of those is advice that cannot work.
        throw const ApiAuthRefusedException();
      }
    } on ApiChallengedException {
      // The edge turned us away. Either we had no key yet or it was
      // rotated; fetch it fresh and give the request one more go before
      // telling the caller the site is unreachable.
      _bypassKey = null;
      if (await _fetchBypassKey() == null) throw _edgeUnreachable;
      try {
        return await send();
      } on ApiChallengedException {
        // Still challenged with a fresh key: the rule isn't matching, and
        // callers only know how to handle "unreachable".
        throw _edgeUnreachable;
      }
    }
  }

  /// The issuer baked into a token, or null if it carries none.
  ///
  /// The server validates the token against *its* Supabase. A token minted
  /// by a different project is simply invalid there, and `getRequestAuth`
  /// reports that as a flat 401 — indistinguishable from an expired session
  /// unless the two issuers are compared.
  String? _issuerOf(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final claims =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final iss = claims['iss'] as String?;
      return iss == null ? null : Uri.tryParse(iss)?.host;
    } catch (_) {
      return null;
    }
  }

  /// Names the project mismatch when that is what a 401 actually means.
  String _authFailureMessage(String token) {
    final tokenIssuer = _issuerOf(token);
    final expected = Uri.parse(AppConfig.supabaseUrl).host;
    if (tokenIssuer != null && tokenIssuer != expected) {
      return 'Sesi ini dari Supabase lain ($tokenIssuer), sementara server '
          'memakai $expected. Keluar lalu masuk lagi.';
    }
    return 'Sesi kamu berakhir. Masuk lagi ya.';
  }

  /// The claims the server will judge, without printing the token itself.
  ///
  /// `getRequestAuth` refuses anything whose role isn't `authenticated`, so
  /// a token that is valid but carries the wrong role fails exactly like a
  /// missing one — indistinguishable from the app side without this.
  String _describeToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return 'not a JWT (${parts.length} parts)';
      Map<String, dynamic> decode(String segment) =>
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(segment))),
              )
              as Map<String, dynamic>;

      final header = decode(parts[0]);
      final claims = decode(parts[1]);
      final exp = claims['exp'] as int?;
      final expiresAt = exp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      // `alg` and `iss` are the two that decide whether the *server* can
      // validate this: an asymmetric alg needs the project's JWKS, and an
      // `iss` pointing at a different project fails whatever the claims say.
      return 'role=${claims['role']} aud=${claims['aud']} '
          'sub=${claims['sub'] == null ? "-" : "set"} '
          'alg=${header['alg']} kid=${header['kid'] == null ? "-" : "set"} '
          'iss=${claims['iss']} '
          'exp=${expiresAt?.toIso8601String() ?? "-"} '
          'expired=${expiresAt != null && expiresAt.isBefore(DateTime.now())}';
    } catch (e) {
      return 'undecodable ($e)';
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body, {
    _MultipartBody? multipart,
    Duration? timeout,
  }) async {
    final deadline = timeout ?? _timeout;
    // Awaited here so the very first request already carries the header.
    await _ensureBypassKey();
    final token = await _accessToken();
    if (token == null) {
      throw const ApiAuthException('Sesi kamu berakhir. Masuk lagi ya.');
    }

    final client = HttpClient()..connectionTimeout = deadline;
    try {
      final bypass = _bypassKey;
      var uri = Uri.parse('${AppConfig.appUrl}$path');
      late HttpClientResponse response;
      late String text;

      // Followed by hand because Dart's HttpClient only auto-follows GET and
      // HEAD. A POST to a host that redirects (the apex answers 308 to the
      // `www` host) otherwise *returns* the redirect body, and a caller that
      // reads a field out of it sees a plausible-looking payload from a
      // request the route never ran.
      for (var hop = 0; ; hop++) {
        final request = await client.openUrl(method, uri).timeout(deadline);
        request.followRedirects = false;
        request.headers
          ..set(HttpHeaders.acceptHeader, 'application/json')
          // The documented transport for native clients: `getRequestAuth`
          // reads this header first and hands the token straight to
          // PostgREST, so RLS and `auth.uid()` resolve. The handoff is
          // explicit that the app must not forge the `@supabase/ssr` cookie.
          ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
        // Satisfies the Vercel firewall rule.
        if (bypass != null) request.headers.set(_bypassHeader, bypass);
        // Some routes authenticate from the browser's `@supabase/ssr` cookie
        // rather than through `getRequestAuth`, and ignore the header above
        // entirely — `/api/scan` is one. Presenting the session in that
        // shape as well is the only way a native client can satisfy them
        // without a change on the server.
        final cookie = _sessionCookie(token);
        if (cookie != null) {
          request.headers.set(HttpHeaders.cookieHeader, cookie);
        }
        if (multipart != null) {
          // The boundary has to travel on the header, not just between the
          // parts — without it the server sees an unparseable body and
          // `formData()` throws, which /api/scan reports as a flat 400.
          request.headers.contentType = ContentType(
            'multipart',
            'form-data',
            parameters: {'boundary': multipart.boundary},
          );
          request.add(multipart.bytes);
        } else if (body != null) {
          request.headers.contentType = ContentType.json;
          request.add(utf8.encode(jsonEncode(body)));
        }

        response = await request.close().timeout(deadline);
        text = await response.transform(utf8.decoder).join();

        final location = response.isRedirect
            ? response.headers.value(HttpHeaders.locationHeader)
            : null;
        if (location == null) break;
        if (hop >= _maxRedirects) {
          throw ApiException(
            'Server mengarahkan berulang kali (${response.statusCode}).',
            statusCode: response.statusCode,
          );
        }
        // Resolved against the current URI so a relative Location works.
        uri = uri.resolve(location);
        if (kDebugMode) debugPrint('[api] $method redirected -> $uri');
      }

      // Debug builds only. The app and the server disagree about what was
      // sent often enough that inferring it from the parsed result is what
      // kept the checkout bug hidden — this prints the wire itself.
      if (kDebugMode) {
        debugPrint(
          '[api] $method $path -> ${response.statusCode}'
          '${bypass == null ? " (no bypass header)" : ""}'
          '${response.headers.value("x-vercel-mitigated") == null ? "" : " MITIGATED"}',
        );
        debugPrint('[api] token: ${_describeToken(token)}');
        if (body != null) debugPrint('[api] request: ${jsonEncode(body)}');
        // Never the body itself — it's a JPEG, and dumping it would bury the
        // rest of the log for the exact requests most in need of reading.
        if (multipart != null) {
          debugPrint('[api] request: multipart ${multipart.bytes.length}B');
        }
        debugPrint(
          '[api] response: '
          '${text.length > 600 ? "${text.substring(0, 600)}..." : text}',
        );
      }

      // Vercel's Attack Challenge Mode answers with a JS challenge page
      // instead of the route. No HTTP client can solve it — only a browser
      // engine can — so say so plainly rather than surfacing "429" or a
      // JSON parse error from an HTML body.
      if (response.headers.value('x-vercel-mitigated') != null) {
        // Distinct from "unreachable": this one is retryable once the
        // bypass header is in hand, and `_retrying` does exactly that.
        throw const ApiChallengedException();
      }

      final decoded = text.isEmpty ? null : jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw ApiException(
          'Respons tidak dikenali dari server (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        // A 403 that names its own reason is the route refusing this action
        // (an unverified phone, say), not the session failing — retrying it
        // with a fresh token would only fail the same way, and the caller
        // needs the server's sentence, not "sesi berakhir".
        final stated = decoded['error'] as String?;
        if (response.statusCode == 403 && stated != null) {
          throw ApiException(
            stated,
            statusCode: response.statusCode,
            payload: decoded,
          );
        }
        // The server's own message is usually the bare word "Unauthorized",
        // which says nothing about *why*; a mismatched issuer is by far the
        // most common cause during local development.
        throw ApiAuthException(_authFailureMessage(token));
      }
      if (response.statusCode == 429) {
        // Two different 429 shapes reach this line. The rate limiter answers
        // with `{error, retryAfter}` in the body; an overloaded upstream
        // answers with only a `Retry-After` header and no such field. Reading
        // both means one wait value regardless of which produced it.
        throw ApiRateLimitedException(
          decoded['error'] as String? ?? 'Terlalu banyak permintaan.',
          retryAfter: _retryAfter(response, decoded),
          payload: decoded,
        );
      }
      if (response.statusCode >= 400) {
        throw ApiException(
          decoded['error'] as String? ??
              decoded['message'] as String? ??
              'Gagal menghubungi server.',
          statusCode: response.statusCode,
          payload: decoded,
        );
      }
      return decoded;
    } on SocketException {
      throw const ApiUnreachableException('Tidak ada koneksi internet.');
    } on TimeoutException {
      throw const ApiUnreachableException(
        'Server tidak merespons. Coba lagi sebentar.',
      );
    } on FormatException {
      throw const ApiException('Respons tidak dikenali dari server.');
    } finally {
      client.close(force: true);
    }
  }

  /// The `@supabase/ssr` cookie name this project's sessions are stored
  /// under: `sb-` + the first label of the Supabase host + `-auth-token`,
  /// which is how supabase-js derives its `storageKey` and therefore what
  /// `createServerClient` looks for.
  static String sessionCookieName(String supabaseUrl) {
    final host = Uri.parse(supabaseUrl).host;
    final label = host.split('.').first;
    return 'sb-$label-auth-token';
  }

  /// `@supabase/ssr` splits a long cookie into `name.0`, `name.1`, … at this
  /// many characters (`MAX_CHUNK_SIZE`), and reads at most five chunks back.
  static const _cookieChunkSize = 3180;

  /// The session encoded the way the browser client writes it: `base64-`
  /// followed by the base64url of the session JSON, chunked if long.
  ///
  /// The refresh token is deliberately left out. A server that found the
  /// access token expired would otherwise refresh it — rotating the refresh
  /// token on the server, where the app never sees the replacement, and
  /// ending the session it was trying to use. Without one, an expired access
  /// token simply fails auth, which [_retrying] already handles by
  /// refreshing on this side and trying again.
  static String? buildSessionCookie(
    String cookieName,
    Session session,
    String accessToken,
  ) {
    final payload = session.toJson()
      ..['access_token'] = accessToken
      ..['refresh_token'] = '';
    // Unpadded base64url, as `stringToBase64URL` emits it.
    final encoded =
        'base64-'
        '${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';

    if (encoded.length <= _cookieChunkSize) return '$cookieName=$encoded';

    final chunks = <String>[];
    for (var i = 0; i * _cookieChunkSize < encoded.length; i++) {
      final start = i * _cookieChunkSize;
      final end = start + _cookieChunkSize;
      chunks.add(
        '$cookieName.$i='
        '${encoded.substring(start, end > encoded.length ? encoded.length : end)}',
      );
    }
    // Only the chunks, never the bare name alongside them: the reader
    // concatenates everything it finds under both.
    return chunks.join('; ');
  }

  String? _sessionCookie(String accessToken) {
    final session = _auth.currentSession;
    if (session == null) return null;
    return buildSessionCookie(
      sessionCookieName(AppConfig.supabaseUrl),
      session,
      accessToken,
    );
  }

  /// PostgREST rejects an expired JWT, and so does `getRequestAuth`'s
  /// `auth.getUser(token)`, so refresh before spending a request on it.
  /// The token as it stands *now*, never a copy kept from sign-in.
  ///
  /// `supabase_flutter` refreshes in the background on a timer, so reading
  /// `currentSession` per call picks up whatever it last minted. Caching the
  /// string instead is the classic version of this bug: it works for an hour
  /// and then 401s forever.
  ///
  /// Refreshed early rather than only once expired. The SDK's own timer uses
  /// a 30-second margin, and its timer is tied to app lifecycle — a long
  /// spell backgrounded can leave a token that is about to die, or has just
  /// died, sitting there on resume.
  Future<String?> _accessToken() async {
    final session = _auth.currentSession;
    if (session == null) return null;

    final expiresAt = session.expiresAt;
    final expiringSoon =
        expiresAt != null &&
        DateTime.fromMillisecondsSinceEpoch(
          expiresAt * 1000,
        ).subtract(_refreshMargin).isBefore(DateTime.now());

    if (!session.isExpired && !expiringSoon) return session.accessToken;
    try {
      final refreshed = await _auth.refreshSession();
      return refreshed.session?.accessToken;
    } on AuthException {
      return null;
    }
  }
}

/// One file part of a [PokepediaApi.postMultipart] request.
class ApiMultipartFile {
  const ApiMultipartFile({
    required this.field,
    required this.filename,
    required this.bytes,
    required this.contentType,
  });

  /// The `FormData` key the route reads this part out of.
  final String field;
  final String filename;
  final Uint8List bytes;

  /// Must be one of the route's allowed types — `/api/scan` rejects anything
  /// outside `image/jpeg`, `image/png`, `image/webp`.
  final String contentType;
}

/// An encoded `multipart/form-data` body plus the boundary its header needs.
class _MultipartBody {
  const _MultipartBody({required this.boundary, required this.bytes});

  final String boundary;
  final Uint8List bytes;
}

/// The header the firewall rule matches on.
const _bypassHeader = 'x-pokepedia-client';

const _edgeUnreachable = ApiUnreachableException(
  'Layanan pengiriman & pembayaran sedang tidak bisa diakses dari '
  'aplikasi. Lanjutkan lewat halaman web.',
);

/// How long to wait before retrying a 429, from whichever of the two shapes
/// the server used.
///
/// The header is read first because it is the one both shapes carry; the body
/// field only exists on the rate limiter's own response.
Duration? _retryAfter(HttpClientResponse response, Map<String, dynamic> body) {
  final header = int.tryParse(response.headers.value('retry-after') ?? '');
  final field = (body['retryAfter'] as num?)?.round();
  final seconds = header ?? field;
  // A zero or negative value is not a wait instruction; treating it as one
  // would busy-loop the caller against a server that is already shedding.
  if (seconds == null || seconds <= 0) return null;
  return Duration(seconds: seconds);
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.payload});

  final String message;
  final int? statusCode;
  final Map<String, dynamic>? payload;

  @override
  String toString() => message;
}

/// The server could not be reached at all — offline, timed out, or blocked
/// by the edge before the route ran. Callers fall back to the web handoff.
class ApiUnreachableException extends ApiException {
  const ApiUnreachableException(super.message);
}

/// Vercel's Attack Challenge Mode answered instead of the route. Internal:
/// callers see [ApiUnreachableException] if the retry with a fresh bypass
/// key doesn't get through either.
class ApiChallengedException extends ApiException {
  const ApiChallengedException()
    : super('Permintaan ditahan oleh proteksi situs.');
}

/// The caller is over a rate limit, or the upstream it depends on is shedding
/// load. [retryAfter] is how long the server asked for, when it said.
///
/// Its own type because the right response is to wait and retry, not to
/// surface a failure — a caller that treats every 4xx alike either hammers a
/// server that is already struggling or gives up on a request that would
/// succeed a second later.
class ApiRateLimitedException extends ApiException {
  const ApiRateLimitedException(super.message, {this.retryAfter, super.payload})
    : super(statusCode: 429);

  final Duration? retryAfter;
}

/// The session is missing, expired, or was refused.
class ApiAuthException extends ApiException {
  const ApiAuthException(super.message);
}

/// The session cannot be recovered: refreshing it was refused, or a freshly
/// minted token was rejected anyway.
///
/// Distinct from [ApiAuthException] on purpose — that one is "this request
/// failed to authenticate", which a refresh usually fixes. This one is the
/// only condition that justifies sending the user back to the login screen.
class ApiSessionExpiredException extends ApiAuthException {
  const ApiSessionExpiredException()
    : super('Sesi kamu sudah berakhir. Masuk lagi untuk melanjutkan.');
}

/// The server refused a token minted seconds earlier.
///
/// Deliberately not an [ApiSessionExpiredException]: signing out and back in
/// changes nothing, because the session was never the problem. The causes are
/// all on the other side — most commonly a route that reads the browser's
/// `@supabase/ssr` cookie instead of the `Authorization` header this client
/// sends, which no native client can satisfy.
class ApiAuthRefusedException extends ApiAuthException {
  const ApiAuthRefusedException()
    : super(
        'Server menolak sesi ini. Bukan karena kamu perlu masuk lagi — coba '
        'lagi sebentar, dan laporkan kalau terus muncul.',
      );
}

final pokepediaApiProvider = Provider(
  (ref) => PokepediaApi(Supabase.instance.client),
);
