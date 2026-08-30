import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_condition.dart';
import '../../../shared/models/card_model.dart';
import 'models/bid_proposal_model.dart';
import 'models/listing_offer_model.dart';
import 'models/my_bid.dart';
import 'models/sent_proposal.dart';
import 'models/proposals_summary.dart';

/// The `cards` columns these rows embed — same list the other repositories
/// hand to [CardModel.fromRow].
const _cardColumns =
    'id, name_id, expansion_code, collector_number, rarity, category, image_url, '
    'illustrator, regulation_mark, language, variant, details';

const _offerColumns =
    '''
slug, condition, quantity, listing_price, current_price, last_actor, status,
buyer_counter_count, seller_counter_count, message, created_at, expires_at,
seller_id, listing:ask_order_id(slug), card:cards!inner($_cardColumns)
''';

const _proposalColumns =
    '''
slug, status, proposed_quantity, proposed_price, condition, message,
created_at, expires_at, seen_at, seller_id,
bid:listings!inner(id, price, user_id, card:cards!inner($_cardColumns))
''';

/// Data access for the buyer's side of negotiation, backed by Supabase.
///
/// Ports `/api/listing-offers*` and `/api/bid-proposals*`, which are thin
/// wrappers over `submit_offer` / `accept_offer` / `counter_offer` /
/// `reject_offer` / `withdraw_offer` / `accept_bid_proposal` /
/// `reject_bid_proposal` — all `SECURITY DEFINER` and granted to
/// `authenticated`, so the app calls them directly. Reads go straight to
/// `listing_offers` / `bid_proposals`, whose RLS already scopes rows to the
/// buyer and seller involved.
class ProposalsRepository {
  ProposalsRepository(this._client);

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  // --- Offers the buyer made on someone's ask -----------------------------

  Future<List<ListingOfferModel>> fetchMyOffers() async {
    final userId = _userId;
    if (userId == null) return const [];

    final rows = await _client
        .from('listing_offers')
        .select(_offerColumns)
        .eq('buyer_id', userId)
        .order('updated_at', ascending: false)
        .limit(50);

    final storeNames = await _storeNamesFor(
      rows.map((r) => r['seller_id'] as String).toSet(),
    );

    return rows
        .map((row) => _mapOffer(row, storeNames[row['seller_id'] as String]))
        .toList();
  }

  /// Offers other buyers made on this user's own asks. Kept for the
  /// Proposals tab's "diterima" side — a buyer-only install simply has none.
  Future<List<ListingOfferModel>> fetchReceivedOffers() async {
    final userId = _userId;
    if (userId == null) return const [];

    final rows = await _client
        .from('listing_offers')
        .select(_offerColumns)
        .eq('seller_id', userId)
        .order('updated_at', ascending: false)
        .limit(50);

    return rows.map((row) => _mapOffer(row, null)).toList();
  }

  /// Ports `POST /api/listing-offers`. [askSlug] is `listings.slug` of the
  /// ask being negotiated.
  Future<String?> submitOffer({
    required String askSlug,
    required int quantity,
    required int price,
    String? message,
  }) {
    return _callRpc('submit_offer', {
      'p_ask_order_slug': askSlug,
      'p_quantity': quantity,
      'p_price': price,
      'p_message': message,
    });
  }

  Future<String?> acceptOffer(String offerSlug) =>
      _callRpc('accept_offer', {'p_offer_slug': offerSlug});

  Future<String?> counterOffer({
    required String offerSlug,
    required int price,
    String? message,
  }) {
    return _callRpc('counter_offer', {
      'p_offer_slug': offerSlug,
      'p_price': price,
      'p_message': message,
    });
  }

  Future<String?> rejectOffer({
    required String offerSlug,
    String? reason,
    String? note,
  }) {
    return _callRpc('reject_offer', {
      'p_offer_slug': offerSlug,
      'p_reason': reason,
      'p_note': note,
    });
  }

  Future<String?> withdrawOffer(String offerSlug) =>
      _callRpc('withdraw_offer', {'p_offer_slug': offerSlug});

  /// Edits a bid's price and quantity. Ports `PATCH /api/listings/bids/[slug]`,
  /// which is a thin wrapper over this RPC.
  ///
  /// The server refuses a bid that has proposals on it (`bid_has_proposals`)
  /// — the UI hides the action for the same reason, but the guard lives here
  /// too because a proposal can land between the list rendering and the tap.
  Future<String?> updateBid({required String slug, int? price, int? quantity}) {
    return _callRpc('update_order_self', {
      'p_slug': slug,
      'p_price': price,
      'p_quantity': quantity,
      'p_condition': null,
      'p_photo_urls': null,
    });
  }

  /// Cancels a bid outright. Ports `DELETE /api/listings?slug=`.
  Future<String?> cancelBid(String slug) =>
      _callRpc('cancel_order_self', {'p_slug': slug});

  /// Proposals this user sent as a seller against other people's WTB bids.
  ///
  /// Ports `SentProposalsList`. The same policy that lets a buyer read
  /// proposals on their bids lets a seller read the ones they sent, so this
  /// is the same table filtered the other way. Archived rows are excluded —
  /// `dismiss_bid_proposal` stamps `seller_archived_at` to clear a settled
  /// proposal off this list.
  Future<List<SentProposalModel>> fetchSentProposals({int limit = 100}) async {
    final userId = _userId;
    if (userId == null) return const [];

    final rows =
        await _client
                .from('bid_proposals')
                .select(
                  'slug, status, proposed_quantity, proposed_price, condition,'
                  'message, created_at, expires_at,'
                  'bid:listings!inner(id, price, user_id,'
                  'cards!inner($_cardColumns))',
                )
                .eq('seller_id', userId)
                .isFilter('seller_archived_at', null)
                .order('created_at', ascending: false)
                .limit(limit)
            as List;
    if (rows.isEmpty) return const [];

    final buyerIds = rows
        .map((r) => (r as Map<String, dynamic>)['bid'] as Map<String, dynamic>)
        .map((bid) => bid['user_id'] as String?)
        .whereType<String>()
        .toSet();
    final usernames = await _usernames(buyerIds);

    return rows.cast<Map<String, dynamic>>().map((row) {
      final bid = row['bid'] as Map<String, dynamic>;
      return SentProposalModel.fromRow(
        row,
        buyerUsername: usernames[bid['user_id']],
      );
    }).toList();
  }

  /// Usernames off `profiles`, which is world-readable — unlike
  /// `seller_profiles`.
  Future<Map<String, String>> _usernames(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows =
        await _client
                .from('profiles')
                .select('id, username')
                .inFilter('id', ids.toList())
            as List;
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        if ((row['username'] as String?)?.isNotEmpty ?? false)
          row['id'] as String: row['username'] as String,
    };
  }

  /// Clears a settled proposal off the sent list. The RPC refuses while the
  /// proposal is still pending, which is why the UI only offers it after.
  Future<String?> dismissSentProposal(String slug) =>
      _callRpc('dismiss_bid_proposal', {'p_proposal_slug': slug});

  /// The user's own open WTB bids, newest first, each carrying how many
  /// proposals are waiting on it.
  ///
  /// Ports the bid half of web's card feed (`/api/listings/bids`). The
  /// proposal counts come from the same policy-scoped `bid_proposals` read
  /// the summary uses, so the number on a row and the number in the market
  /// banner can't disagree.
  Future<List<MyBidModel>> fetchMyBids({int limit = 100}) async {
    final userId = _userId;
    if (userId == null) return const [];

    final rows =
        await _client
                .from('listings')
                .select(
                  'id, slug, price, condition, quantity, qty_locked,'
                  'created_at, expires_at, cards!inner($_cardColumns)',
                )
                .eq('user_id', userId)
                .eq('side', 'bid')
                .eq('status', 'open')
                .order('created_at', ascending: false)
                .limit(limit)
            as List;
    if (rows.isEmpty) return const [];

    final countsByBid = await _proposalCountsByBid();
    return rows.cast<Map<String, dynamic>>().map((row) {
      final counts = countsByBid[(row['id'] as num).toInt()];
      return MyBidModel.fromRow(
        row,
        pendingProposals: counts?.pending ?? 0,
        totalProposals: counts?.total ?? 0,
        latestProposalAt: counts?.latest,
      );
    }).toList();
  }

  /// Proposal counts per `bid_order_id`, for the bids this user owns.
  ///
  /// Totals as well as pending, because the card feed reports both — and the
  /// newest proposal's timestamp, which is what orders that feed.
  Future<Map<int, ({int pending, int total, DateTime? latest})>>
  _proposalCountsByBid() async {
    final userId = _userId;
    if (userId == null) return const {};

    final rows =
        await _client
                .from('bid_proposals')
                .select(
                  'bid_order_id, status, created_at,'
                  'bid:listings!inner(user_id)',
                )
                .limit(500)
            as List;

    final counts = <int, ({int pending, int total, DateTime? latest})>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final bid = row['bid'] as Map<String, dynamic>?;
      // The policy also returns proposals this user *sent*; only the ones on
      // their own bids belong on a bid row.
      if (bid == null || bid['user_id'] != userId) continue;
      final bidId = (row['bid_order_id'] as num?)?.toInt();
      if (bidId == null) continue;

      final current =
          counts[bidId] ?? (pending: 0, total: 0, latest: null as DateTime?);
      final createdAt = DateTime.tryParse(
        row['created_at'] as String? ?? '',
      )?.toLocal();
      final latest = switch ((current.latest, createdAt)) {
        (null, final next) => next,
        (final existing, null) => existing,
        (final existing!, final next!) =>
          next.isAfter(existing) ? next : existing,
      };

      counts[bidId] = (
        pending: current.pending + (row['status'] == 'pending' ? 1 : 0),
        total: current.total + 1,
        latest: latest,
      );
    }
    return counts;
  }

  /// Marks proposals on this user's bids as read.
  ///
  /// Without this the market banner's "baru" count never clears: `seen_at`
  /// is only ever set here, and the badge counts pending proposals whose
  /// `seen_at` is null. The RPC is a no-op on rows already seen and on rows
  /// belonging to someone else, so a stale slug costs nothing.
  ///
  /// Best-effort: failing to record a read is not worth interrupting the
  /// list the user came to see.
  Future<void> markProposalsSeen(Iterable<String> slugs) async {
    if (_userId == null) return;
    await Future.wait([
      for (final slug in slugs)
        _client
            .rpc('mark_bid_proposal_seen', params: {'p_proposal_slug': slug})
            .catchError((_) => null),
    ]);
  }

  /// Ports `getProposalsSummary` — what the market page's banner shows.
  ///
  /// Web computes this with a service client; the app uses the caller's own
  /// token, which reaches the same rows: `listings` is own-row for the
  /// buyer's bids, `bid_proposals`' policy exposes both sides of a
  /// negotiation this user is party to, and `seller_profiles` is self-read.
  Future<ProposalsSummary> fetchSummary() async {
    final userId = _userId;
    if (userId == null) return const ProposalsSummary();

    final results = await Future.wait([
      _client
          .from('listings')
          .select('id')
          .eq('user_id', userId)
          .eq('side', 'bid')
          .eq('status', 'open'),
      // One read for both directions: the policy returns proposals on this
      // user's bids *and* the ones they sent as a seller, so they're split
      // apart below rather than fetched twice.
      _client
          .from('bid_proposals')
          .select(
            'status, seen_at, seller_id, seller_archived_at,'
            'bid:listings!inner(user_id)',
          )
          .limit(200),
      _client
          .from('seller_profiles')
          .select('is_active')
          .eq('user_id', userId)
          .maybeSingle(),
    ]);

    final bidCount = (results[0] as List).length;
    final profile = results[2] as Map<String, dynamic>?;

    var receivedPending = 0;
    var receivedPendingUnseen = 0;
    var receivedTotal = 0;
    var sentPending = 0;
    var sentTotal = 0;

    for (final row in (results[1] as List).cast<Map<String, dynamic>>()) {
      final bid = row['bid'] as Map<String, dynamic>?;
      final status = row['status'] as String?;

      if (bid != null && bid['user_id'] == userId) {
        receivedTotal++;
        if (status == 'pending') {
          receivedPending++;
          if (row['seen_at'] == null) receivedPendingUnseen++;
        }
      } else if (row['seller_id'] == userId) {
        // Web drops archived rows from the sent side.
        if (row['seller_archived_at'] != null) continue;
        sentTotal++;
        if (status == 'pending') sentPending++;
      }
    }

    return ProposalsSummary(
      receivedPending: receivedPending,
      receivedPendingUnseen: receivedPendingUnseen,
      receivedTotal: receivedTotal,
      sentPending: sentPending,
      sentTotal: sentTotal,
      bidCount: bidCount,
      isActiveSeller: profile?['is_active'] as bool? ?? false,
    );
  }

  // --- Proposals sellers made on the buyer's bids -------------------------

  /// Proposals against this user's own WTB bids — the buyer accepts or
  /// rejects them. RLS lets the bid's owner read these rows.
  Future<List<BidProposalModel>> fetchBidProposals() async {
    final userId = _userId;
    if (userId == null) return const [];

    final rows = await _client
        .from('bid_proposals')
        .select(_proposalColumns)
        .order('created_at', ascending: false)
        .limit(50);

    // The policy also exposes proposals this user *sent* as a seller; the
    // buyer inbox only wants the ones on their own bids.
    final mine = rows.where((row) {
      final bid = row['bid'] as Map<String, dynamic>?;
      return bid != null && bid['user_id'] == userId;
    }).toList();
    if (mine.isEmpty) return const [];

    final storeNames = await _storeNamesFor(
      mine.map((r) => r['seller_id'] as String).toSet(),
    );

    return mine.map((row) {
      final bid = row['bid'] as Map<String, dynamic>;
      final card = CardModel.fromRow(bid['card'] as Map<String, dynamic>);
      return BidProposalModel(
        slug: row['slug'] as String? ?? '',
        card: card,
        condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
        proposedQuantity: (row['proposed_quantity'] as num?)?.toInt() ?? 1,
        sellerStoreName: storeNames[row['seller_id'] as String] ?? 'Penjual',
        status: BidProposalStatusX.fromRaw(row['status'] as String?),
        createdAt: _date(row['created_at']),
        expiresAt: _date(row['expires_at']),
        seenAt: _date(row['seen_at']),
        message: row['message'] as String?,
      );
    }).toList();
  }

  Future<String?> acceptBidProposal(String proposalSlug) =>
      _callRpc('accept_bid_proposal', {'p_proposal_slug': proposalSlug});

  Future<String?> rejectBidProposal({
    required String proposalSlug,
    String? reason,
    String? note,
  }) {
    return _callRpc('reject_bid_proposal', {
      'p_proposal_slug': proposalSlug,
      'p_reason': reason,
      'p_note': note,
    });
  }

  // --- Shared helpers -----------------------------------------------------

  /// Calls an RPC that answers `{ ok: true }` or `{ error: '...' }`,
  /// returning null on success and a human-readable message otherwise.
  Future<String?> _callRpc(String name, Map<String, dynamic> params) async {
    try {
      final result = await _client.rpc(name, params: params);
      if (result is Map<String, dynamic>) {
        final error = result['error'] as String?;
        if (error != null) return _messageFor(error);
      }
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Indonesian copy for the error strings these RPCs return.
  /// Exposed for tests: the refusal codes are the contract between
  /// `submit_offer` and what a buyer reads, and an unmapped one is silent.
  @visibleForTesting
  String debugMessageFor(String code) => _messageFor(code);

  String _messageFor(String code) {
    switch (code) {
      case 'unauthorized':
      case 'unauthenticated':
        return 'Masuk dulu untuk melanjutkan.';
      case 'phone_not_verified':
        return 'Nomor HP kamu belum diverifikasi.';
      case 'not_found':
      case 'offer_not_found':
      case 'proposal_not_found':
        return 'Penawaran tidak ditemukan atau sudah berakhir.';
      case 'not_pending':
        return 'Penawaran ini sudah direspons.';
      case 'expired':
        return 'Penawaran ini sudah kedaluwarsa.';
      case 'self_offer':
      case 'cannot_offer_on_own_listing':
        return 'Kamu tidak bisa menawar listing sendiri.';
      // `submit_offer` refuses a second live offer on the same listing.
      // Named rather than generic: the buyer's move is to open the one they
      // already have, not to try again.
      case 'offer_already_pending':
        return 'Kamu sudah punya penawaran aktif untuk listing ini.';
      case 'offer_already_accepted':
        return 'Kamu sudah punya harga penawaran aktif untuk listing ini. '
            'Tunggu sampai kedaluwarsa.';
      case 'offer_not_below_price':
        return 'Penawaran harus di bawah harga listing.';
      case 'not_an_ask_order':
        return 'Order ini bukan listing jual.';
      case 'order_not_available':
        return 'Listing sudah tidak tersedia.';
      case 'message_too_long':
        return 'Pesan maksimal 280 karakter.';
      case 'bidding_banned':
        return 'Akun kamu sedang dibatasi.';
      case 'listing_unavailable':
      case 'insufficient_quantity':
        return 'Stok listing sudah tidak mencukupi.';
      case 'offers_not_accepted':
        return 'Penjual tidak menerima penawaran untuk listing ini.';
      case 'counter_limit_reached':
        return 'Batas tawar-menawar sudah tercapai.';
      case 'invalid_price':
        return 'Harga penawaran tidak valid.';
      // Bid edit and cancel (`update_order_self` / `cancel_order_self`).
      case 'bid_has_proposals':
        return 'Bid ini sudah menerima proposal — tidak bisa diubah.';
      case 'order_locked_by_buyer':
        return 'Bid ini sedang diproses pembeli.';
      case 'quantity_below_locked':
        return 'Jumlah tidak boleh kurang dari yang sudah terkunci.';
      case 'invalid_quantity':
        return 'Jumlah harus antara 1 dan 99.';
      case 'order_not_editable':
      case 'order_not_cancellable':
        return 'Bid ini sudah tidak bisa diubah.';
      case 'order_not_found':
        return 'Bid tidak ditemukan.';
      case 'nothing_to_update':
        return 'Tidak ada perubahan untuk disimpan.';
      case 'trading_disabled':
        return 'Kartu ini belum bisa diperdagangkan.';
      default:
        return 'Gagal memproses penawaran. Coba lagi.';
    }
  }

  Future<Map<String, String>> _storeNamesFor(Set<String> sellerIds) async {
    if (sellerIds.isEmpty) return const {};
    try {
      final rows = await _client
          .from('seller_profiles')
          .select('user_id, store_name')
          .inFilter('user_id', sellerIds.toList());
      return {
        for (final row in rows)
          row['user_id'] as String: row['store_name'] as String? ?? 'Toko',
      };
    } catch (_) {
      return const {};
    }
  }

  ListingOfferModel _mapOffer(Map<String, dynamic> row, String? storeName) {
    return ListingOfferModel(
      slug: row['slug'] as String? ?? '',
      card: CardModel.fromRow(row['card'] as Map<String, dynamic>),
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      listingPrice: (row['listing_price'] as num?)?.toInt() ?? 0,
      currentPrice: (row['current_price'] as num?)?.toInt() ?? 0,
      lastActor: (row['last_actor'] as String?) == 'seller'
          ? OfferActor.seller
          : OfferActor.buyer,
      status: _offerStatus(row['status'] as String?),
      storeName: storeName ?? 'Toko',
      createdAt: _date(row['created_at']),
      expiresAt: _date(row['expires_at']),
      buyerCounterCount: (row['buyer_counter_count'] as num?)?.toInt() ?? 0,
      sellerCounterCount: (row['seller_counter_count'] as num?)?.toInt() ?? 0,
      listingSlug:
          (row['listing'] as Map<String, dynamic>?)?['slug'] as String? ?? '',
    );
  }

  static DateTime _date(dynamic raw) =>
      DateTime.tryParse(raw as String? ?? '')?.toLocal() ?? DateTime.now();

  static OfferStatus _offerStatus(String? raw) {
    switch (raw) {
      case 'accepted':
        return OfferStatus.accepted;
      case 'rejected':
        return OfferStatus.rejected;
      case 'expired':
        return OfferStatus.expired;
      case 'withdrawn':
        return OfferStatus.withdrawn;
      default:
        return OfferStatus.pending;
    }
  }
}
