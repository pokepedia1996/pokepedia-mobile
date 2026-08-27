import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import 'models/seller_listing.dart';

/// The seller's own listings, and the toggles their product list acts on.
///
/// The web mutates these through `/api/seller/listings*`, but those routes
/// are thin wrappers over RPCs that are themselves granted to
/// `authenticated` — and they were never converted to accept a bearer token,
/// so the app couldn't call them anyway. Reading is the same story:
/// `listings_select_own` is `auth.uid() = user_id`. So this talks to
/// Postgres directly, the way the cart already does with `add_to_cart`.
///
/// Every RPC here takes `listings.slug` (a uuid), not the integer id.
class SellerListingsRepository {
  SellerListingsRepository(this._client);

  final SupabaseClient _client;

  static const _columns =
      'id, slug, price, condition, quantity, qty_locked, status, '
      'accepts_offers, auto_relist, view_count, created_at, archived_at, '
      'expires_at, photo_urls, '
      'cards!inner(id, name_id, expansion_code, collector_number, rarity, '
      'category, image_url, illustrator, regulation_mark, language, variant, '
      'details)';

  Future<List<SellerListing>> fetchListings({
    required SellerListingBucket bucket,
    String query = '',
    int limit = 100,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    var request = _client
        .from('listings')
        .select(_columns)
        .eq('user_id', userId)
        .eq('side', 'ask');

    // Archiving is the only predicate SQL can settle here: "active" also
    // depends on `expires_at` against now, and mixing that into PostgREST
    // filters would still leave the bucketing split across two places. The
    // rest is decided by `SellerListing.bucket`, which is the one copy of
    // the rule.
    request = bucket.isArchived
        ? request.not('archived_at', 'is', null)
        : request.isFilter('archived_at', null);

    final rows = await request
        .order('created_at', ascending: false)
        .limit(limit);
    final listings = rows
        .map(SellerListing.fromRow)
        .where((listing) => listing.bucket == bucket)
        .toList();

    // Filtered here rather than in SQL: the searchable text lives on the
    // joined card, and PostgREST can't filter an embedded resource without
    // dropping the rows that don't match into a separate request.
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return listings;
    return listings
        .where(
          (l) =>
              l.card.name.toLowerCase().contains(needle) ||
              l.card.collectorNumber.toLowerCase().contains(needle) ||
              l.card.expansionCode.toLowerCase().contains(needle),
        )
        .toList();
  }

  /// The two toggles web's Preferensi tab writes.
  ///
  /// Web sends these through `PUT /api/seller/profile` (`listing_defaults`),
  /// but that route just upserts `seller_profiles`, and
  /// `seller_profiles_self_update` lets the owner write their own row — the
  /// counters are the only columns `protect_admin_columns` guards. So the app
  /// reads and writes them directly and stays off the firewalled path.
  Future<ListingDefaults> fetchListingDefaults() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const ListingDefaults();

    final row = await _client
        .from('seller_profiles')
        .select('default_auto_relist, default_accepts_offers')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return const ListingDefaults();
    return ListingDefaults(
      autoRelist: row['default_auto_relist'] as bool? ?? false,
      acceptsOffers: row['default_accepts_offers'] as bool? ?? false,
    );
  }

  Future<String?> saveListingDefaults(ListingDefaults defaults) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Sesi berakhir.';
    try {
      await _client.from('seller_profiles').upsert({
        'user_id': userId,
        'default_auto_relist': defaults.autoRelist,
        'default_accepts_offers': defaults.acceptsOffers,
      }, onConflict: 'user_id');
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// The seller's unposted drafts. `listing_drafts` is own-row under RLS,
  /// so this reads it directly rather than through a route.
  Future<List<SellerDraft>> fetchDrafts({int limit = 100}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows =
        await _client
                .from('listing_drafts')
                .select(
                  'id, price, condition, quantity, photo_urls, updated_at,'
                  'cards!inner(id, name_id, expansion_code, collector_number,'
                  'rarity, category, image_url, illustrator, regulation_mark,'
                  'language, variant, details)',
                )
                .eq('user_id', userId)
                .order('updated_at', ascending: false)
                .limit(limit)
            as List;
    return rows
        .map((r) => SellerDraft.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<String?> deleteDraft(int id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Sesi berakhir.';
    try {
      await _client
          .from('listing_drafts')
          .delete()
          .eq('id', id)
          .eq('user_id', userId);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Ports `POST /api/seller/listings/delete` → `archive_listing`.
  Future<String?> archive(String slug) =>
      _call('archive_listing', {'p_slug': slug});

  /// Ports `unarchiveListing`.
  Future<String?> unarchive(String slug) =>
      _call('unarchive_listing', {'p_slug': slug});

  /// Ports `restockListing` — adds stock back to a sold-out listing.
  Future<String?> restock(String slug, int quantity) =>
      _call('restock_listing', {'p_slug': slug, 'p_quantity': quantity});

  Future<String?> setAcceptsOffers(String slug, bool enabled) => _call(
    'set_listing_accepts_offers',
    {'p_slug': slug, 'p_enabled': enabled},
  );

  Future<String?> setAutoRelist(String slug, bool enabled) =>
      _call('set_listing_auto_relist', {'p_slug': slug, 'p_enabled': enabled});

  /// Every one of these RPCs returns `jsonb`, using an `error` key rather
  /// than raising — so a business rejection ("listing sudah terjual") comes
  /// back as data and has to be read, not caught.
  Future<String?> _call(String fn, Map<String, dynamic> params) async {
    try {
      final result = await _client.rpc(fn, params: params);
      if (result is Map && result['error'] != null) {
        return _message(result['error'].toString());
      }
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  static String _message(String code) => switch (code) {
    'not_found' => 'Listing tidak ditemukan.',
    'forbidden' || 'not_owner' => 'Listing ini bukan milik kamu.',
    'has_locked_quantity' =>
      'Ada pembeli yang sedang checkout listing ini. Coba lagi sebentar.',
    'already_archived' => 'Listing sudah diarsipkan.',
    'not_archived' => 'Listing ini tidak diarsipkan.',
    'invalid_quantity' => 'Jumlah tidak valid.',
    'listing_matched' => 'Listing sudah terjual.',
    _ => 'Gagal memproses listing ($code).',
  };
}

final sellerListingsRepositoryProvider = Provider(
  (ref) => SellerListingsRepository(ref.read(supabaseClientProvider)),
);
