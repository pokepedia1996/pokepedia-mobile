import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_condition.dart';
import '../../../shared/models/card_model.dart';
import 'models/bid_proposal_model.dart';
import 'models/listing_offer_model.dart';

/// The `cards` columns these rows embed — same list the other repositories
/// hand to [CardModel.fromRow].
const _cardColumns =
    'id, name_id, expansion_code, collector_number, rarity, category, image_url, '
    'illustrator, regulation_mark, language, variant, details';

const _offerColumns = '''
slug, condition, quantity, listing_price, current_price, last_actor, status,
buyer_counter_count, seller_counter_count, message, created_at, expires_at,
seller_id, card:cards!inner($_cardColumns)
''';

const _proposalColumns = '''
slug, status, proposed_quantity, proposed_price, condition, message,
created_at, expires_at, seller_id,
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
        sellerStoreName:
            storeNames[row['seller_id'] as String] ?? 'Penjual',
        status: _proposalStatus(row['status'] as String?),
        createdAt: _date(row['created_at']),
        expiresAt: _date(row['expires_at']),
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
  String _messageFor(String code) {
    switch (code) {
      case 'unauthorized':
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
        return 'Kamu tidak bisa menawar listing sendiri.';
      case 'listing_unavailable':
      case 'insufficient_quantity':
        return 'Stok listing sudah tidak mencukupi.';
      case 'offers_not_accepted':
        return 'Penjual tidak menerima penawaran untuk listing ini.';
      case 'counter_limit_reached':
        return 'Batas tawar-menawar sudah tercapai.';
      case 'invalid_price':
        return 'Harga penawaran tidak valid.';
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

  static BidProposalStatus _proposalStatus(String? raw) {
    switch (raw) {
      case 'accepted':
        return BidProposalStatus.accepted;
      case 'rejected':
        return BidProposalStatus.rejected;
      case 'expired':
        return BidProposalStatus.expired;
      case 'withdrawn':
        return BidProposalStatus.withdrawn;
      default:
        return BidProposalStatus.pending;
    }
  }
}
