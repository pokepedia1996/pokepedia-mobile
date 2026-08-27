import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  /// The value of the `x-pokepedia-client` header that pokepedia.id's
  /// firewall rule looks for.
  ///
  /// Held in Supabase Vault rather than compiled into the app, so it can be
  /// rotated without a release; fetched once per app run and re-fetched if
  /// the edge ever challenges us again, which is what a rotation looks like
  /// from here.
  String? _bypassKey;

  Future<String?> _fetchBypassKey() async {
    try {
      final response = await _client.functions.invoke('client-config');
      final data = response.data;
      if (data is Map && data['bypassKey'] is String) {
        return data['bypassKey'] as String;
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

  /// Retries a 401 exactly once.
  ///
  /// The server collapses every auth failure into 401, including a transient
  /// GoTrue outage. Treating a single one as "session dead" would sign out
  /// every user of the app during a brief provider incident, so one failure
  /// buys a token refresh and a second attempt before the caller hears about
  /// it.
  Future<Map<String, dynamic>> _retrying(
    Future<Map<String, dynamic>> Function() send,
  ) async {
    try {
      return await send();
    } on ApiAuthException {
      try {
        await _auth.refreshSession();
      } on AuthException {
        // Refresh failed too — fall through and let the retry report it.
      }
      return send();
    } on ApiChallengedException {
      // The edge turned us away. Either we had no key yet or it was
      // rotated; fetch it fresh and give the request one more go before
      // telling the caller the site is unreachable.
      _bypassKey = await _fetchBypassKey();
      if (_bypassKey == null) throw _edgeUnreachable;
      try {
        return await send();
      } on ApiChallengedException {
        // Still challenged with a fresh key: the rule isn't matching, and
        // callers only know how to handle "unreachable".
        throw _edgeUnreachable;
      }
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final token = await _accessToken();
    if (token == null) {
      throw const ApiAuthException('Sesi kamu berakhir. Masuk lagi ya.');
    }

    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .openUrl(method, Uri.parse('${AppConfig.appUrl}$path'))
          .timeout(_timeout);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      // Satisfies the Vercel firewall rule. Absent on the very first call of
      // a run, which is what the retry above is for.
      final bypass = _bypassKey;
      if (bypass != null) request.headers.set(_bypassHeader, bypass);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }

      final response = await request.close().timeout(_timeout);
      final text = await response.transform(utf8.decoder).join();

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
        throw ApiAuthException(
          decoded['error'] as String? ?? 'Sesi kamu berakhir. Masuk lagi ya.',
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

  /// PostgREST rejects an expired JWT, and so does `getRequestAuth`'s
  /// `auth.getUser(token)`, so refresh before spending a request on it.
  Future<String?> _accessToken() async {
    final session = _auth.currentSession;
    if (session == null) return null;
    if (!session.isExpired) return session.accessToken;
    try {
      final refreshed = await _auth.refreshSession();
      return refreshed.session?.accessToken;
    } on AuthException {
      return null;
    }
  }
}

/// The header the firewall rule matches on.
const _bypassHeader = 'x-pokepedia-client';

const _edgeUnreachable = ApiUnreachableException(
  'Layanan pengiriman & pembayaran sedang tidak bisa diakses dari '
  'aplikasi. Lanjutkan lewat halaman web.',
);

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

/// The session is missing, expired, or was refused.
class ApiAuthException extends ApiException {
  const ApiAuthException(super.message);
}

final pokepediaApiProvider = Provider(
  (ref) => PokepediaApi(Supabase.instance.client),
);
