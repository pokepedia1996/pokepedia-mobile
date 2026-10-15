import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of `get_store_identities` — the storefront fields of another
/// user, which a direct `seller_profiles` read can't return because that
/// table is self-select only under RLS.
///
/// Carries no `is_verified`: the RPC doesn't return it, and web reads that
/// through its service client instead. `city_name` arrived with migration
/// `add_city_to_store_identities`; against an older backend it's just null.
class StoreIdentity {
  const StoreIdentity({
    required this.userId,
    this.storeName,
    this.storeSlug,
    this.storeLogoUrl,
    this.cityName,
  });

  factory StoreIdentity.fromRow(Map<String, dynamic> row) => StoreIdentity(
    userId: row['user_id'] as String,
    storeName: row['store_name'] as String?,
    storeSlug: row['store_slug'] as String?,
    storeLogoUrl: row['store_logo_url'] as String?,
    cityName: row['city_name'] as String?,
  );

  final String userId;
  final String? storeName;
  final String? storeSlug;
  final String? storeLogoUrl;

  /// `seller_profiles.city_name` — where the seller ships from.
  final String? cityName;

  /// Keys a `get_store_identities` result by user id. Rows without a
  /// `user_id` are skipped rather than failing the whole batch.
  static Map<String, StoreIdentity> parseRows(Object? rows) {
    if (rows is! List) return const {};
    return {
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (row['user_id'] is String)
          row['user_id'] as String: StoreIdentity.fromRow(row),
    };
  }
}

/// Storefront fields for [userIds], keyed by user id. Granted to `anon` too,
/// so signed-out browsing shows store names; a failure falls back to usernames.
Future<Map<String, StoreIdentity>> fetchStoreIdentities(
  SupabaseClient client,
  Iterable<String> userIds,
) async {
  final ids = userIds.toSet().toList();
  if (ids.isEmpty) return const {};
  try {
    final rows = await client.rpc(
      'get_store_identities',
      params: {'p_user_ids': ids},
    );
    return StoreIdentity.parseRows(rows);
  } on PostgrestException {
    return const {};
  }
}
