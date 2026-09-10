import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_condition.dart';
import 'models/trading_models.dart';

/// Writes to the order book. Ports `POST /api/listings` — which is itself a
/// thin wrapper over the `place_order` RPC — straight onto Supabase, since
/// that RPC is `SECURITY DEFINER` and granted to `authenticated`, so every
/// gate (phone verification, seller profile, self-trade, duplicates) is
/// enforced server-side exactly as it is for the web.
///
/// The web route additionally records a device fingerprint for its
/// linked-account self-trade heuristic; the app has no fingerprint source,
/// and `place_order`'s own `device_users` join still covers accounts linked
/// by any previously recorded device.
class TradingRepository {
  TradingRepository(this._client);

  final SupabaseClient _client;

  /// Places a bid (WTB) or ask (WTS). [replace] expires the user's existing
  /// open order on this side first — the "duplicate" recovery path.
  Future<PlaceOrderResult> placeOrder({
    required int cardId,
    required String side,
    required int price,
    required CardCondition condition,
    required int quantity,
    String? variantKey,
    bool replace = false,
    bool autoRelist = false,
    List<String> photoUrls = const [],
  }) async {
    try {
      final result = await _client.rpc(
        'place_order',
        params: {
          'p_card_id': cardId,
          'p_variant_key': variantKey,
          'p_side': side,
          'p_price': price,
          'p_condition': condition.raw,
          'p_quantity': quantity,
          'p_replace': replace,
          'p_auto_relist': autoRelist,
          'p_photo_urls': side == 'ask' ? photoUrls : null,
        },
      );

      final payload = result as Map<String, dynamic>?;
      if (payload == null) return const PlaceOrderResult.failed('unknown');
      if (payload['ok'] == true) return const PlaceOrderResult.ok();

      final error = payload['error'] as String? ?? 'unknown';
      if (error == 'duplicate') {
        return PlaceOrderResult.duplicate(
          (payload['existing_price'] as num?)?.toInt() ?? 0,
        );
      }
      return PlaceOrderResult.failed(error);
    } on PostgrestException {
      return const PlaceOrderResult.failed('unknown');
    }
  }

  /// Uploads a seller's own photos of the card to the `listing-photos`
  /// bucket and returns their public URLs, for `place_order`'s
  /// `p_photo_urls` (required on asks of Rp100.000 and up).
  ///
  /// The web posts these through `/api/seller/listing-photos`, which stores
  /// them in R2; Storage's own policy already scopes writes to
  /// `listing-photos/{uid}/…`, so the app uploads directly instead.
  Future<List<String>> uploadListingPhotos(List<File> files) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || files.isEmpty) return const [];

    final bucket = _client.storage.from('listing-photos');
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final extension = file.path.split('.').last.toLowerCase();
      final path =
          '$userId/${DateTime.now().millisecondsSinceEpoch}_$i.$extension';
      await bucket.upload(
        path,
        file,
        fileOptions: const FileOptions(upsert: false),
      );
      urls.add(bucket.getPublicUrl(path));
    }
    return urls;
  }

  /// How much a bid price level can still absorb, and how many buyers are
  /// behind it — what the proposal sheet caps its quantity to.
  ///
  /// Ports `fetchLevel` in `bid-proposal-modal.tsx`. The caller's own bids
  /// are excluded: you can't propose to yourself, and counting them would
  /// promise quantity the broadcast will never reach.
  Future<({int buyerCount, int availableQty})> fetchBidLevel({
    required int cardId,
    required CardCondition condition,
    required int price,
    String? variantKey,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return (buyerCount: 0, availableQty: 0);

    var query = _client
        .from('listings')
        .select('quantity, qty_locked, user_id')
        .eq('side', 'bid')
        .eq('status', 'open')
        .eq('card_id', cardId)
        .eq('condition', condition.raw)
        .eq('price', price)
        .neq('user_id', me);
    query = variantKey == null
        ? query.isFilter('variant_key', null)
        : query.eq('variant_key', variantKey);

    final rows = await query as List;
    var available = 0;
    var buyers = 0;
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final remaining =
          ((row['quantity'] as num?)?.toInt() ?? 0) -
          ((row['qty_locked'] as num?)?.toInt() ?? 0);
      if (remaining <= 0) continue;
      available += remaining;
      buyers++;
    }
    return (buyerCount: buyers, availableQty: available);
  }

  /// Offers the caller's card to every buyer bidding at one price level.
  ///
  /// Ports `POST /api/bid-proposals/broadcast`, which only validates the
  /// photo URLs before calling this RPC — and the app uploads to the same
  /// `listing-photos/{uid}/` prefix that validation checks for.
  ///
  /// A broadcast rather than a message to one buyer, which is why the order
  /// book can act on a price level that carries no listing slug.
  Future<({int sentCount, String? error})> broadcastBidProposal({
    required int cardId,
    required CardCondition condition,
    required int price,
    required int quantity,
    List<String> photoUrls = const [],
    String? variantKey,
    String? message,
    int? proposedPrice,
  }) async {
    try {
      final result = await _client.rpc(
        'submit_bid_proposal_broadcast',
        params: {
          'p_card_id': cardId,
          'p_variant_key': variantKey,
          'p_condition': condition.raw,
          'p_price': price,
          'p_quantity': quantity,
          'p_photos': photoUrls,
          'p_message': message,
          'p_proposed_price': proposedPrice,
        },
      );
      final row = result is Map ? result : const {};
      final error = row['error'] as String?;
      if (error != null) {
        return (sentCount: 0, error: _proposalErrorMessage(error));
      }
      return (
        sentCount: (row['sent_count'] as num?)?.toInt() ?? 0,
        error: null,
      );
    } on PostgrestException catch (e) {
      return (sentCount: 0, error: e.message);
    }
  }

  /// Proposes to **one** bid, by its listing slug — `submit_bid_proposal`.
  ///
  /// The sibling of [broadcastBidProposal], and the difference is who hears
  /// about it: the broadcast offers the card to everyone bidding at a price
  /// level, this answers the single wanted-ad the seller is looking at. The
  /// order book has only a price level to work with, so it broadcasts; the
  /// bid detail page has the listing itself.
  ///
  /// The condition can't be chosen — the RPC rejects anything but the bid's
  /// own with `condition_mismatch`.
  Future<({String? proposalSlug, String? error})> submitBidProposal({
    required String bidSlug,
    required CardCondition condition,
    required int quantity,
    List<String> photoUrls = const [],
    String? message,
    int? proposedPrice,
  }) async {
    try {
      final result = await _client.rpc(
        'submit_bid_proposal',
        params: {
          'p_bid_order_slug': bidSlug,
          'p_quantity': quantity,
          'p_condition': condition.raw,
          'p_photos': photoUrls,
          'p_message': message,
          'p_proposed_price': proposedPrice,
        },
      );
      final row = result is Map ? result : const {};
      final error = row['error'] as String?;
      if (error != null) {
        return (proposalSlug: null, error: _proposalErrorMessage(error));
      }
      return (proposalSlug: row['proposal_slug'] as String?, error: null);
    } on PostgrestException catch (e) {
      return (proposalSlug: null, error: e.message);
    }
  }

  String _proposalErrorMessage(String code) => switch (code) {
    'unauthorized' ||
    'not_authenticated' => 'Masuk dulu untuk mengirim proposal',
    'phone_not_verified' => 'Verifikasi nomor teleponmu dulu',
    'seller_not_active' => 'Aktifkan toko dulu untuk mengirim proposal',
    'no_bids' => 'Tidak ada bid di harga ini lagi',
    'photos_required' || 'invalid_photos' => 'Unggah foto kartumu dulu',
    'rate_limited' => 'Terlalu banyak proposal. Coba lagi nanti.',
    // The rest only `submit_bid_proposal` answers with — proposing to one
    // named bid can fail in ways a broadcast to a price level cannot.
    'cannot_propose_on_own_bid' => 'Ini bid kamu sendiri',
    'proposal_already_pending' =>
      'Kamu sudah mengirim proposal untuk bid ini. Cek halaman Proposal.',
    'order_not_found' ||
    'order_not_available' ||
    'not_a_bid_order' => 'Bid ini sudah tidak aktif',
    'insufficient_quantity' => 'Jumlahnya melebihi yang dicari pembeli',
    'condition_mismatch' =>
      'Kondisi kartumu harus sama dengan yang dicari pembeli',
    'invalid_proposed_price' => 'Harga jualmu tidak boleh di bawah bid',
    'invalid_quantity' => 'Jumlahnya tidak valid',
    'seller_profile_incomplete' => 'Lengkapi profil tokomu dulu',
    'no_couriers' => 'Atur kurir pengirimanmu dulu',
    'trading_disabled' => 'Kartu ini belum bisa diperdagangkan',
    _ => 'Gagal mengirim proposal',
  };

  /// Indonesian copy for the error codes the two proposal RPCs return.
  /// Exposed for tests: those codes are the contract between the RPC and
  /// what a seller reads, and an unmapped one says nothing.
  @visibleForTesting
  String debugMessageFor(String code) => _proposalErrorMessage(code);

  /// The gates `place_order` enforces, read before the form opens.
  /// `profiles_private` and `seller_profiles` are both own-row-only under
  /// RLS, so a failure here just means "not eligible".
  Future<TradeEligibility> fetchEligibility() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const TradeEligibility();

    try {
      final results = await Future.wait([
        _client
            .from('profiles_private')
            .select('phone, phone_verified_at')
            .eq('id', userId)
            .maybeSingle(),
        _client
            .from('profiles')
            .select('bidding_banned')
            .eq('id', userId)
            .maybeSingle(),
        _client
            .from('seller_profiles')
            .select('is_active, accepted_couriers')
            .eq('user_id', userId)
            .maybeSingle(),
      ]);

      final private = results[0];
      final profile = results[1];
      final seller = results[2];
      final couriers = seller?['accepted_couriers'] as List?;

      return TradeEligibility(
        phoneVerified:
            private?['phone'] != null && private?['phone_verified_at'] != null,
        biddingBanned: profile?['bidding_banned'] as bool? ?? false,
        sellerActive: seller?['is_active'] as bool? ?? false,
        hasCouriers: couriers != null && couriers.isNotEmpty,
      );
    } catch (_) {
      return const TradeEligibility();
    }
  }

  /// Ports `GET /api/listings/matching-asks` — open asks of the same card
  /// and condition at or below the bid price, cheapest first, so the buyer
  /// is offered "buy now" before their bid goes on the book. Own listings
  /// are excluded (the RPC would reject a self-trade anyway).
  Future<List<MatchingAsk>> fetchMatchingAsks({
    required int cardId,
    required int price,
    required CardCondition condition,
    String? variantKey,
    int limit = 5,
  }) async {
    final userId = _client.auth.currentUser?.id;

    var query = _client
        .from('listings')
        .select(
          'slug, card_id, price, condition, quantity, qty_locked, user_id, variant_key',
        )
        .eq('card_id', cardId)
        .eq('side', 'ask')
        .eq('status', 'open')
        .eq('condition', condition.raw)
        .lte('price', price)
        .isFilter('archived_at', null);
    if (userId != null) query = query.neq('user_id', userId);

    final rows = await query.order('price', ascending: true).limit(limit);

    final matches = rows.where((row) {
      final available =
          (row['quantity'] as int? ?? 0) - (row['qty_locked'] as int? ?? 0);
      final rowVariant = row['variant_key'] as String?;
      return available > 0 && (rowVariant ?? '') == (variantKey ?? '');
    }).toList();
    if (matches.isEmpty) return const [];

    // Store names come from a separate table (`listings.user_id` and
    // `seller_profiles.user_id` both point at `auth.users`, so PostgREST
    // can't embed them), same two-step the listings query uses.
    final sellerIds = matches
        .map((r) => r['user_id'] as String)
        .toSet()
        .toList();
    final stores = await _client
        .from('seller_profiles')
        .select('user_id, store_slug, store_name')
        .inFilter('user_id', sellerIds);
    final storeByUser = {for (final s in stores) s['user_id'] as String: s};

    return matches.map((row) {
      final store = storeByUser[row['user_id'] as String];
      return MatchingAsk(
        slug: row['slug'] as String? ?? '',
        cardId: (row['card_id'] as num).toInt(),
        price: (row['price'] as num?)?.toInt() ?? 0,
        condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
        available:
            (row['quantity'] as int? ?? 0) - (row['qty_locked'] as int? ?? 0),
        storeSlug: store?['store_slug'] as String? ?? '',
        storeName: store?['store_name'] as String? ?? 'Toko',
      );
    }).toList();
  }
}
