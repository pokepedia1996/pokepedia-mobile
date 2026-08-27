import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/wallet_models.dart';

/// Data access for the Wallet feature: `public.wallets` for the balance and
/// `get_wallet_activity` for the ledger.
///
/// The activity RPC rather than a direct `wallet_ledger` read: it already
/// buckets each row (penghasilan / refund / penarikan) and applies the
/// caller scoping, so the two clients agree on what a row means.
class WalletRepository {
  WalletRepository(this._client);

  final SupabaseClient _client;

  Future<int> fetchBalance() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;
    final row = await _client
        .from('wallets')
        .select('balance')
        .eq('user_id', userId)
        .maybeSingle();
    return (row?['balance'] as num?)?.toInt() ?? 0;
  }

  Future<List<WalletActivity>> fetchActivity({int limit = 30}) async {
    if (_client.auth.currentUser == null) return const [];
    final rows =
        await _client.rpc(
              'get_wallet_activity',
              params: {'p_limit': limit, 'p_bucket': 'all'},
            )
            as List;
    return rows
        .map((r) => WalletActivity.fromRow(r as Map<String, dynamic>))
        .toList();
  }
}
