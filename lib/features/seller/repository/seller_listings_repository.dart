import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_condition.dart';
import '../../../shared/utils/card_pricing.dart';
import 'models/seller_listing.dart';
import '../../../core/errors/user_message.dart';

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
      return userFacingError(e);
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
                  'auto_relist, accepts_offers,'
                  'cards!inner(id, name_id, expansion_code, collector_number,'
                  'rarity, category, image_url, illustrator, regulation_mark,'
                  'language, variant, details)',
                )
                .eq('user_id', userId)
                .order('updated_at', ascending: false)
                .limit(limit)
            as List;
    final drafts = rows
        .map((r) => SellerDraft.fromRow(r as Map<String, dynamic>))
        .toList();

    // Priced, or the card has no market price to offer and the "pakai harga
    // pasaran" button on every draft has nothing to do. `cards` carries no
    // price — it comes from the price cache — so without this the draft
    // editor could only ever show an empty field and a dead sparkle.
    final priced = await priceCards(_client, [for (final d in drafts) d.card]);
    final byId = {for (final card in priced) card.id: card};
    return [
      for (final draft in drafts)
        if (byId[draft.card.id] case final card?)
          draft.withCard(card)
        else
          draft,
    ];
  }

  /// Writes one draft's editable fields. Only what is passed is sent, so a
  /// quantity change can't blank a price the seller has already set.
  Future<String?> updateDraft(
    int id, {
    int? quantity,
    int? price,
    bool? autoRelist,
    bool? acceptsOffers,
    CardCondition? condition,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Sesi berakhir.';

    final patch = <String, dynamic>{
      if (quantity != null) 'quantity': quantity,
      if (price != null) 'price': price,
      if (autoRelist != null) 'auto_relist': autoRelist,
      if (acceptsOffers != null) 'accepts_offers': acceptsOffers,
      if (condition != null) 'condition': condition.raw,
    };
    if (patch.isEmpty) return null;

    try {
      await _client
          .from('listing_drafts')
          .update(patch)
          .eq('id', id)
          .eq('user_id', userId);
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  /// Replaces a draft's photos with [urls].
  ///
  /// Whole-list, not append: the sheet that calls this shows the draft's
  /// photos and lets them be removed, so what it hands back is the answer,
  /// not an addition to it.
  Future<String?> setDraftPhotos(int id, List<String> urls) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Sesi berakhir.';
    try {
      await _client
          .from('listing_drafts')
          .update({'photo_urls': urls})
          .eq('id', id)
          .eq('user_id', userId);
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  /// Applies one switch to the ticked drafts at once — the bulk rows in the
  /// listing page's dropdown.
  ///
  /// One statement rather than a call per draft: the seller is saying one
  /// thing about a set of them, and a loop would leave it half-applied if it
  /// failed partway, with no way to tell which half.
  Future<String?> updateDrafts({
    required List<int> ids,
    bool? autoRelist,
    bool? acceptsOffers,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Sesi berakhir.';
    if (ids.isEmpty) return null;

    final patch = <String, dynamic>{
      if (autoRelist != null) 'auto_relist': autoRelist,
      if (acceptsOffers != null) 'accepts_offers': acceptsOffers,
    };
    if (patch.isEmpty) return null;

    try {
      await _client
          .from('listing_drafts')
          .update(patch)
          // Scoped to the ticked rows. The owner check stays: `ids` comes
          // from the client, and the table's policy is the only thing
          // standing between a hand-made list and someone else's drafts.
          .inFilter('id', ids)
          .eq('user_id', userId);
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  /// Creates a draft for each of [picks] through `add_listing_draft`.
  ///
  /// Drafts, not listings: the sheet that calls this asks only *which*
  /// cards and *how many*. Price, condition and photos are decided
  /// afterwards on the cards themselves, which is why a seller can pick a
  /// dozen at once here without being asked a dozen questions.
  ///
  /// The function is idempotent per (card, variant, condition) — picking a
  /// card already drafted bumps its quantity rather than making a second row.
  Future<({int added, String? error})> addDrafts(
    List<({int cardId, int quantity})> picks,
  ) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return (added: 0, error: 'Sesi berakhir.');

    var added = 0;
    String? failure;
    for (final pick in picks) {
      try {
        await _client.rpc(
          'add_listing_draft',
          params: {
            'p_user_id': userId,
            'p_card_id': pick.cardId,
            // The function clamps to 1..99 and, on a card already drafted,
            // adds to what is there rather than replacing it — so picking
            // three of something with two in Draft leaves five.
            'p_qty': pick.quantity,
          },
        );
        added++;
      } on PostgrestException catch (e) {
        // One bad card doesn't lose the rest of the pick — the seller would
        // have to work out which of twelve failed and choose them again.
        failure ??= userFacingError(e);
      }
    }
    return (added: added, error: failure);
  }

  /// Posts one draft to the market through `confirm_listing_draft`, which
  /// places the ask and clears the draft in one transaction.
  ///
  /// Server-side on purpose: a draft becoming a listing is two writes that
  /// must not half-happen, and the rules for what a listing may be are the
  /// database's, not this client's.
  Future<String?> confirmDraft(int id) async {
    try {
      final result = await _client.rpc(
        'confirm_listing_draft',
        params: {'p_draft_id': id},
      );
      // The function answers with jsonb; a failure is reported in it rather
      // than thrown, so a silent "nothing happened" is not mistaken for
      // success.
      if (result is Map && result['error'] != null) {
        return result['error'].toString();
      }
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  /// "Impor dari Portofolio" — turns the seller's collection into drafts.
  /// Returns how many rows were created, or an error.
  Future<({int inserted, String? error})> importDraftsFromCollection() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return (inserted: 0, error: 'Sesi berakhir.');
    try {
      final rows = await _client.rpc(
        'import_listing_drafts_from_collection',
        params: {'p_user_id': userId},
      );
      final first = rows is List && rows.isNotEmpty ? rows.first : null;
      final inserted = first is Map
          ? (first['inserted_count'] as num?)?.toInt() ?? 0
          : 0;
      return (inserted: inserted, error: null);
    } on PostgrestException catch (e) {
      return (inserted: 0, error: userFacingError(e));
    }
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
      return userFacingError(e);
    }
  }

  /// Ports `POST /api/seller/listings/delete` → `archive_listing`.
  Future<String?> archive(String slug) =>
      _call('archive_listing', {'p_slug': slug});

  /// Ports `POST /api/seller/listings/delete` → `delete_listing`, which is
  /// a soft delete: the row keeps its history, it just leaves every list.
  ///
  /// Distinct from [archive], which is reversible from the Arsip tab. This
  /// one is not, which is why the caller confirms first.
  Future<String?> deletePermanent(String slug) =>
      _call('delete_listing', {'p_slug': slug});

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
      return userFacingError(e);
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
    'has_active_payment' =>
      'Ada pembeli yang sedang membayar listing ini. Coba lagi nanti.',
    _ => 'Gagal memproses listing ($code).',
  };
}

final sellerListingsRepositoryProvider = Provider(
  (ref) => SellerListingsRepository(ref.read(supabaseClientProvider)),
);
