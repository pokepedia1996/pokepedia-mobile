import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/referral_models.dart';

/// Ajak Teman + Koin RPCs. The referral and Koin tables have no client
/// grants, so everything goes through these SECURITY DEFINER functions.
class ReferralRepository {
  ReferralRepository(this._client);

  final SupabaseClient _client;

  bool get _signedIn => _client.auth.currentUser != null;

  /// Page size 20; pass `offset` 0, 20, 40… while `hasMore`.
  Future<ReferralDashboard> fetchDashboard({
    ReferralFilter filter = ReferralFilter.all,
    int offset = 0,
  }) async {
    if (!_signedIn) return ReferralDashboard.empty;
    final data = await _client.rpc(
      'get_referral_dashboard',
      params: {'p_filter': filter.name, 'p_offset': offset},
    );
    return ReferralDashboard.fromJson(data);
  }

  /// Idempotent: an already-opened pack returns its stored result.
  Future<PackResult> openPack(String packId) async {
    final data = await _client.rpc(
      'open_referral_pack',
      params: {'p_pack_id': packId},
    );
    return PackResult.fromJson(data);
  }

  Future<List<ReferralTier>> fetchOdds() async {
    final data = await _client.rpc('get_referral_odds');
    return ReferralTier.listFromJson(referralPayload(data)['tiers']);
  }

  /// Call before opening the reminder share sheet.
  Future<RemindResult> markReminded(String refereeId) async {
    final data = await _client.rpc(
      'mark_referral_reminded',
      params: {'p_referee_id': refereeId},
    );
    return RemindResult.fromJson(data);
  }

  Future<KoinBalance> fetchKoinBalance() async {
    if (!_signedIn) return KoinBalance.zero;
    return KoinBalance.fromJson(await _client.rpc('get_koin_balance'));
  }

  Future<KoinHistoryPage> fetchKoinHistory({int offset = 0}) async {
    if (!_signedIn) return const KoinHistoryPage();
    final data = await _client.rpc(
      'get_koin_history',
      params: {'p_offset': offset},
    );
    return KoinHistoryPage.fromJson(data);
  }
}
