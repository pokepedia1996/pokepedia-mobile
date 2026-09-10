import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import 'models/listing_offer.dart';

/// Raised when an offer RPC answers with a business error rather than
/// throwing — the RPCs return `{error: '<code>'}` instead of failing, so the
/// happy path has to check the payload.
class OfferActionException implements Exception {
  const OfferActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Offers buyers have made on this seller's listings.
///
/// Talks to Postgres directly rather than to web's `/api/listing-offers/*`.
/// The four mutations are `accept_offer`, `reject_offer`, `counter_offer` and
/// `mark_offer_seen`, all SECURITY DEFINER and all granted to
/// `authenticated`, so the routes wrapping them add nothing the app needs.
/// Reads are covered by `listing_offers_self_select`
/// (`buyer_id = auth.uid() OR seller_id = auth.uid()`); web reaches for the
/// service client there only to join tables this fetches separately.
class OffersRepository {
  OffersRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  static const _columns =
      'slug, status, quantity, listing_price, current_price, last_actor, '
      'buyer_counter_count, seller_counter_count, condition, variant_key, '
      'message, history, rejection_reason, rejection_note, expires_at, '
      'responded_at, created_at, seen_at, buyer_id, seller_id, card_id, '
      'order_item_id, qty_used, '
      'listings:ask_order_id(slug), '
      'cards:card_id(id, name_id, image_url, expansion_code, collector_number,'
      ' variant), '
      'order_items:order_item_id(status)';

  /// Every offer made to this seller, newest movement first.
  ///
  /// Fetched whole rather than per listing because the product list needs the
  /// per-listing badge counts anyway, and one query of a few hundred rows
  /// beats one per row.
  Future<List<ListingOffer>> fetchReceivedOffers({int limit = 200}) async {
    final me = _uid;
    if (me == null) return const [];

    final rows =
        await _client
                .from('listing_offers')
                .select(_columns)
                .eq('seller_id', me)
                .order('updated_at', ascending: false)
                .limit(limit)
            as List;
    if (rows.isEmpty) return const [];

    final offers = rows
        .cast<Map<String, dynamic>>()
        .map(ListingOffer.fromRow)
        .toList();

    // One batched profile read for the whole page rather than one per offer.
    // `Profiles are viewable by everyone`, so this needs no elevation.
    final buyerIds = offers
        .map((o) => o.buyerId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    if (buyerIds.isEmpty) return offers;

    final profiles =
        await _client
                .from('profiles')
                .select('id, username, avatar_url')
                .inFilter('id', buyerIds.toList())
            as List;
    final byId = {
      for (final row in profiles.cast<Map<String, dynamic>>())
        row['id'] as String: row,
    };

    return [
      for (final offer in offers)
        offer.withBuyer(
          username: byId[offer.buyerId]?['username'] as String?,
          avatarUrl: byId[offer.buyerId]?['avatar_url'] as String?,
        ),
    ];
  }

  Future<void> accept(String offerSlug) => _run('accept_offer', {
    'p_offer_slug': offerSlug,
  }, fallback: 'Gagal menerima penawaran');

  Future<void> reject(String offerSlug, {String? note}) =>
      _run('reject_offer', {
        'p_offer_slug': offerSlug,
        // Web sends a null reason and only ever collects the free-text note;
        // the RPC's `p_reason` is for a picker that no client uses yet.
        'p_reason': null,
        'p_note': (note?.trim().isNotEmpty ?? false) ? note!.trim() : null,
      }, fallback: 'Gagal menolak penawaran');

  Future<void> counter(
    String offerSlug, {
    required int price,
    String? message,
  }) => _run('counter_offer', {
    'p_offer_slug': offerSlug,
    'p_price': price,
    'p_message': (message?.trim().isNotEmpty ?? false) ? message!.trim() : null,
  }, fallback: 'Gagal mengirim tawaran balik');

  /// Clears the unread mark. Best-effort by design: a seller who has read an
  /// offer has read it whether or not the write lands, and failing the screen
  /// over a badge would be worse than the stale badge.
  Future<void> markSeen(String offerSlug) async {
    try {
      await _client.rpc('mark_offer_seen', params: {'p_offer_slug': offerSlug});
    } catch (_) {
      // Swallowed on purpose — see above.
    }
  }

  Future<void> _run(
    String fn,
    Map<String, dynamic> params, {
    required String fallback,
  }) async {
    final Object? data;
    try {
      data = await _client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      throw OfferActionException(e.message);
    } catch (_) {
      throw OfferActionException(fallback);
    }

    // A returned `error` key is the normal failure path here, not an
    // exception: the RPCs report refusals as data so the caller can map them.
    final code = data is Map ? data['error'] as String? : null;
    if (code != null) {
      throw OfferActionException(offerErrorMessage(code, fallback));
    }
  }
}

/// The RPC refusal codes, in the wording web's routes use.
///
/// Kept as one table rather than three per-action ones: the codes don't
/// overlap in meaning, and a seller reading "Bukan giliran kamu" does not
/// care which endpoint phrased it.
String offerErrorMessage(String code, String fallback) => switch (code) {
  'unauthorized' => 'Sesi habis. Silakan login ulang.',
  'offer_not_found' => 'Penawaran tidak ditemukan',
  'offer_not_pending' => 'Penawaran sudah diproses',
  'offer_expired' => 'Penawaran sudah kadaluwarsa',
  'not_participant' => 'Penawaran ini bukan milik kamu',
  'not_your_turn' => 'Bukan giliran kamu untuk membalas',
  'order_not_found' => 'Listing tidak ditemukan',
  'order_not_available' => 'Listing sudah tidak tersedia',
  'cannot_offer_on_own_listing' => 'Tidak bisa menerima penawaran sendiri',
  'insufficient_quantity' => 'Stok tidak mencukupi',
  'seller_unavailable' => 'Penjual sudah tidak aktif',
  'same_device_self_trade' =>
    'Tidak dapat bertransaksi dengan akun lain di perangkat yang sama.',
  'note_too_long' => 'Catatan maksimal 500 karakter',
  'message_too_long' => 'Pesan maksimal 280 karakter',
  'invalid_price' => 'Harga tidak valid',
  'trading_disabled' => 'Kartu ini sedang tidak bisa diperdagangkan',
  'price_above_listing' => 'Penawaran balik tidak boleh di atas harga listing',
  'counter_must_raise' =>
    'Tawaran balik harus lebih tinggi dari tawaran saat ini',
  'counter_must_lower' =>
    'Tawaran balik harus lebih rendah dari tawaran saat ini',
  'counter_limit_reached' =>
    'Batas 5 penawaran balik tercapai. Terima atau tolak.',
  _ => fallback,
};

final offersRepositoryProvider = Provider<OffersRepository>(
  (ref) => OffersRepository(ref.read(supabaseClientProvider)),
);
