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
  PokepediaApi(this._auth);

  final GoTrueClient _auth;

  static const _timeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> get(String path) => _retrying(
    () => _send('GET', path, null),
  );

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) => _retrying(() => _send('POST', path, body));

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
        throw const ApiUnreachableException(
          'Layanan pengiriman & pembayaran sedang tidak bisa diakses dari '
          'aplikasi. Lanjutkan lewat halaman web.',
        );
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

/// The session is missing, expired, or was refused.
class ApiAuthException extends ApiException {
  const ApiAuthException(super.message);
}

final pokepediaApiProvider = Provider(
  (ref) => PokepediaApi(Supabase.instance.client.auth),
);
