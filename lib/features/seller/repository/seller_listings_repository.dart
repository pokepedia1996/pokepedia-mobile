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
      'expires_at, '
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

    if (bucket.isArchived) {
      request = request.not('archived_at', 'is', null);
    } else {
      // An archived listing keeps its old status, so every other bucket has
      // to exclude it or the same row shows up twice.
      request = request
          .eq('status', bucket.status!)
          .isFilter('archived_at', null);
    }

    final rows = await request.order('created_at', ascending: false).limit(limit);
    final listings = rows.map(SellerListing.fromRow).toList();

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

  /// Ports `POST /api/seller/listings/delete` → `archive_listing`.
  Future<String?> archive(String slug) => _call('archive_listing', {'p_slug': slug});

  /// Ports `unarchiveListing`.
  Future<String?> unarchive(String slug) =>
      _call('unarchive_listing', {'p_slug': slug});

  /// Ports `restockListing` — adds stock back to a sold-out listing.
  Future<String?> restock(String slug, int quantity) =>
      _call('restock_listing', {'p_slug': slug, 'p_quantity': quantity});

  Future<String?> setAcceptsOffers(String slug, bool enabled) =>
      _call('set_listing_accepts_offers', {'p_slug': slug, 'p_enabled': enabled});

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
