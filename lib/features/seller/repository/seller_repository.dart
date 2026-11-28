import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import 'models/my_reliability.dart';
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

  /// Ports web's `get_my_reliability` read. Granted to `authenticated` and
  /// scoped by `auth.uid()`, so the app calls it on its own session.
  Future<MyReliability?> fetchMyReliability() async {
    final result = await _client.rpc('get_my_reliability');
    return MyReliability.fromJson(result);
  }

  /// Whether the Jual tab shows the dashboard rather than Buka Toko: web's
  /// `isBrandNewSeller` turned around (`app/seller/page.tsx`).
  ///
  /// A store name is not part of it. Web keeps the profile step optional
  /// and shows the username when there is no name, so a seller who set up
  /// pickup and couriers there without one was sent back through Buka Toko
  /// here, which rewrote their couriers, pickup and store link.
  Future<bool> hasStore() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final results = await Future.wait<Object?>([
      _client
          .from('seller_profiles')
          .select('is_active, items_sold_count')
          .eq('user_id', userId)
          .maybeSingle(),
      // Every bucket, drafts included, as web's `listingCounts` sums them.
      _client.rpc('get_seller_listing_tab_counts'),
    ]);
    final seller = results[0] as Map<String, dynamic>?;
    final counts = results[1];

    return !isBrandNewSeller(
      sellerActive: seller?['is_active'] as bool? ?? false,
      listingTotal: counts is Map
          ? counts.values.whereType<num>().fold(0, (sum, n) => sum + n.toInt())
          : 0,
      itemsSold: (seller?['items_sold_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Web's `isBrandNewSeller` (`features/seller/domain/seller-setup.ts`): no
/// store yet means not active (`is_active` follows a pickup address and a
/// courier), no listing in any bucket, and nothing ever sold. Saving a
/// pickup address from Alamat alone leaves a seller brand new, as on web.
bool isBrandNewSeller({
  required bool sellerActive,
  required int listingTotal,
  required int itemsSold,
}) => !sellerActive && listingTotal == 0 && itemsSold == 0;

final sellerRepositoryProvider = Provider(
  (ref) => SellerRepository(ref.watch(supabaseClientProvider)),
);
