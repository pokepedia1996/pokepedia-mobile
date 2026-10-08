import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:pokepedia_mobile/features/market/repository/market_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A store opened by username (Akun, a user profile, the seller dashboard)
/// used to wait for a slug lookup that could only miss before asking for the
/// username, so it opened a whole round trip slower than the same store from
/// the market. Both are asked at once now.
Map<String, dynamic> _store(String slug) => {
  'user_id': 'u1',
  'store_slug': slug,
  'store_name': 'panda',
  'username': 'satoshi',
};

void main() {
  late List<String> started;
  late int inFlight;
  late int maxInFlight;

  MarketRepository repo({required bool slugHits, required bool userHits}) {
    started = [];
    inFlight = 0;
    maxInFlight = 0;
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      httpClient: MockClient((request) async {
        final rpc = request.url.pathSegments.last;
        started.add(rpc);
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        inFlight--;
        final body = switch (rpc) {
          'get_seller_storefront_by_slug' => slugHits ? [_store('panda')] : [],
          'get_seller_storefront_by_username' =>
            userHits ? [_store('panda')] : [],
          // The listing count.
          _ => [
            {'total_count': 75},
          ],
        };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    return MarketRepository(client);
  }

  test('a username opens the store in the same time as a slug', () async {
    final store = await repo(
      slugHits: false,
      userHits: true,
    ).fetchStore('satoshi');

    expect(store?.handle, 'panda');
    // Both lookups were out at once, not one after the other.
    expect(maxInFlight, 2);
    expect(started.take(2).toSet(), {
      'get_seller_storefront_by_slug',
      'get_seller_storefront_by_username',
    });
  });

  test('a slug still wins when the handle is both', () async {
    final store = await repo(slugHits: true, userHits: true).fetchStore('x');
    expect(store?.handle, 'panda');
  });

  test('finding the store asks for nothing else', () async {
    // The listing count used to be awaited here, and the listings RPC that
    // supplies it walks every listing the seller has — the page sat on
    // "Memuat" for it before the first 20 were even requested.
    await repo(slugHits: true, userHits: false).fetchStore('panda');
    expect(started, hasLength(2));
    expect(started, isNot(contains('get_recent_marketplace_listings')));
  });

  test('the count comes on its own, when asked', () async {
    final r = repo(slugHits: true, userHits: false);
    expect(await r.fetchStoreListingCount('u1'), 75);
    expect(started, ['get_recent_marketplace_listings']);
  });

  test('neither found is no store', () async {
    expect(
      await repo(slugHits: false, userHits: false).fetchStore('nobody'),
      isNull,
    );
  });
}
