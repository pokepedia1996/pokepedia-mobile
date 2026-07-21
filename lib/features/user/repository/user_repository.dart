import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/user_model.dart';

const _profileColumns = 'id, username, bio, created_at, role, is_collection_public';

/// Data access for the User profile / directory feature, backed by
/// Supabase. `profiles` and `user_reputation` both reference `auth.users`
/// independently (no FK between them), so reputation is fetched in a
/// second batched query and merged in Dart.
class UserRepository {
  UserRepository(this._client);

  final SupabaseClient _client;

  Future<List<UserModel>> search(String query) async {
    final q = query.trim();
    final profileRows = await _client
        .from('profiles')
        .select(_profileColumns)
        .ilike('username', '%$q%')
        .not('username', 'is', null)
        .order('created_at', ascending: false)
        .limit(20);

    return _hydrate(profileRows);
  }

  Future<UserModel?> fetchByUsername(String username) async {
    final row = await _client
        .from('profiles')
        .select(_profileColumns)
        .eq('username', username)
        .maybeSingle();
    if (row == null) return null;
    final hydrated = await _hydrate([row]);
    return hydrated.first;
  }

  Future<List<UserModel>> _hydrate(List<Map<String, dynamic>> profileRows) async {
    if (profileRows.isEmpty) return const [];

    final ids = profileRows.map((r) => r['id'] as String).toList();
    final reputationRows = await _client
        .from('user_reputation')
        .select('user_id, total_trades, positive_pct')
        .inFilter('user_id', ids);
    final reputationById = {for (final r in reputationRows) r['user_id'] as String: r};

    return profileRows.map((row) {
      final reputation = reputationById[row['id'] as String];
      return UserModel.fromRow({...row, ...?reputation});
    }).toList();
  }
}
