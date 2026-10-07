import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/network/pokepedia_api.dart';
import 'package:pokepedia_mobile/features/promos/repository/promo_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _client() => SupabaseClient('http://localhost', 'anon-key');

class _RecordingApi extends PokepediaApi {
  _RecordingApi() : super(_client());

  final calls = <String>[];
  Map<String, dynamic>? body;

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    calls.add('post $path');
    this.body = body;
    return const {};
  }

  @override
  Future<Map<String, dynamic>> postAnonymous(
    String path,
    Map<String, dynamic> body,
  ) async {
    calls.add('anonymous $path');
    this.body = body;
    return const {};
  }
}

void main() {
  group('requestHeaders', () {
    test('anonymous: firewall header only, no session at all', () {
      final headers = PokepediaApi.requestHeaders(bypass: 'k3y');

      expect(headers[bypassHeader], 'k3y');
      expect(headers.containsKey(HttpHeaders.authorizationHeader), isFalse);
      expect(headers.containsKey(HttpHeaders.cookieHeader), isFalse);
      expect(headers[HttpHeaders.acceptHeader], 'application/json');
    });

    test('authenticated: bearer and cookie travel with the firewall header', () {
      final headers = PokepediaApi.requestHeaders(
        bearer: 'tok',
        cookie: 'sb-x-auth-token=base64-abc',
        bypass: 'k3y',
      );

      expect(headers[HttpHeaders.authorizationHeader], 'Bearer tok');
      expect(headers[HttpHeaders.cookieHeader], 'sb-x-auth-token=base64-abc');
      expect(headers[bypassHeader], 'k3y');
    });

    test('no key in hand means no empty firewall header', () {
      expect(
        PokepediaApi.requestHeaders(bearer: 'tok').containsKey(bypassHeader),
        isFalse,
      );
    });
  });

  test('a signed-out promo event goes out anonymously', () async {
    final api = _RecordingApi();
    final repository = PromoRepository(_client(), api);

    await repository.logEvent(7, PromoPopupEvent.impression);

    expect(api.calls, ['anonymous /api/promos/events']);
    expect(api.body, {'popupId': 7, 'event': 'impression'});
  });
}
