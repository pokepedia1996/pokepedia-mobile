import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/buyer_action_counts.dart';

/// Reads `get_buyer_action_counts`, granted to `authenticated` — the same
/// RPC web's `BuyerActionProvider` calls.
class BuyerActionRepository {
  BuyerActionRepository(this._client);

  final SupabaseClient _client;

  Future<BuyerActionCounts> fetchCounts() async {
    if (_client.auth.currentUser == null) return BuyerActionCounts.zero;
    final data = await _client.rpc('get_buyer_action_counts');
    return BuyerActionCounts.fromJson(data);
  }
}
