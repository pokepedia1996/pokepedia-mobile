import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/seller_dashboard.dart';

/// The seller's own store identity, for the "Lihat Toko" link.
class SellerIdentity {
  const SellerIdentity({this.username, this.storeSlug, this.isActive = false});

  final String? username;
  final String? storeSlug;

  /// `seller_profiles.is_active` — false while the store is set up or on
  /// vacation, which is what tells the dashboard to show the setup banner
  /// rather than pretending the store is live.
  final bool isActive;

  /// Ports the page's `storeHref`: the store slug when there is one, else
  /// the username, else no link at all.
  ///
  /// Blank counts as absent. A `store_slug` of `''` is not null, so a plain
  /// `??` would hand back an empty handle, and `/market/` routes to a path
  /// with no `:handle` segment at all.
  String? get storeHandle => _present(storeSlug) ?? _present(username);

  static String? _present(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value;
}

/// Data access for the seller dashboard.
///
/// Everything here runs on the seller's own Supabase session: the RPC is
/// granted to `authenticated` and reads `auth.uid()` itself, and both table
/// reads are own-row under `seller_profiles`' and `profiles`' RLS. So unlike
/// checkout, no part of this needs the web's API routes.
class SellerRepository {
  SellerRepository(this._client);

  final SupabaseClient _client;

  /// Ports `loadDashboard`'s `get_seller_performance` call. Returns null
  /// when the RPC fails or comes back shapeless, which the page renders as
  /// the "Gagal memuat data dasbor" banner over an empty payload — same as
  /// the web, rather than an error screen.
  Future<DashboardPayload?> fetchPerformance(int windowDays) async {
    try {
      final result = await _client.rpc(
        'get_seller_performance',
        params: {'p_days': windowDays},
      );
      final row = result is List
          ? (result.isEmpty ? null : result.first)
          : result;
      if (row is! Map<String, dynamic>) return null;
      return DashboardPayload.fromRow(row, windowDays);
    } on PostgrestException {
      return null;
    }
  }

  Future<SellerIdentity> fetchIdentity() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const SellerIdentity();

    final results = await Future.wait([
      _client
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .maybeSingle(),
      _client
          .from('seller_profiles')
          .select('store_slug, is_active')
          .eq('user_id', userId)
          .maybeSingle(),
    ]);

    final profile = results[0];
    final seller = results[1];
    return SellerIdentity(
      username: profile?['username'] as String?,
      storeSlug: seller?['store_slug'] as String?,
      isActive: seller?['is_active'] as bool? ?? false,
    );
  }

  /// True once the user has a `seller_profiles` row at all — the app only
  /// offers the dashboard to sellers, and onboarding a new one is a web
  /// flow (it writes store details the app has no form for yet).
  Future<bool> hasStore() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await _client
        .from('seller_profiles')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }
}

final sellerRepositoryProvider = Provider(
  (ref) => SellerRepository(Supabase.instance.client),
);
