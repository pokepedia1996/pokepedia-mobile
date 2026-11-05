import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/user_message.dart';
import '../../../core/network/pokepedia_api.dart';
import '../../../shared/utils/postgrest_embed.dart';
import 'models/dispute_model.dart';
import 'models/open_dispute.dart';

/// `DISPUTE_DETAIL_SELECT` in `features/disputes/data/disputes.ts`, minus the
/// columns no screen here reads. `disputes_party_read` and its siblings on
/// events and evidence scope it to the buyer and seller.
const _detailColumns =
    'id, slug, current_status, reason, reason_category, short_quantity, '
    'requested_resolution, outcome, proposed_refund_amount, '
    'return_courier, return_tracking, return_requested_at, return_deadline_at, '
    'response_deadline_at, opened_at, resolved_at, '
    'evidence_requested_from, evidence_request_due_at, '
    'settlements!inner(slug, buyer_id, seller_id, escrow_amount, '
    'shipping_cost, condition, '
    'order_items!inner(slug, card_id, order_id, order_number, match_price, '
    'matched_quantity, package_order:orders!order_id(order_number), '
    'cards(name_id, image_url, expansion_code, collector_number))), '
    'dispute_events(event_type, actor_role, payload, created_at), '
    'dispute_evidence(id, submitted_by_role, evidence_type, url, body, '
    'submitted_at)';

const _evidenceBucket = 'dispute-evidence';

/// One dispute's detail and the buyer's and seller's moves on it — web's
/// `features/disputes` for everyone but admin.
///
/// Reads go straight to Postgres under the caller's token; every action goes
/// through `/api/disputes/[id]/*` (or the settlement and order-item routes
/// web uses), which own the rate limits, role checks and error copy.
class DisputesRepository {
  DisputesRepository(this._client, this._api);

  final SupabaseClient _client;
  final PokepediaApi _api;

  String? get _uid => _client.auth.currentUser?.id;

  /// The dispute behind [slug], as the caller sees it. Null when it doesn't
  /// exist or the caller is neither its buyer nor its seller.
  Future<DisputeModel?> fetchDispute(String slug) async {
    final me = _uid;
    if (me == null) return null;
    final row = await _client
        .from('disputes')
        .select(_detailColumns)
        .eq('slug', slug.toLowerCase())
        .maybeSingle();
    if (row == null) return null;

    final settlement = embeddedRow(row['settlements']);
    final role = settlement?['seller_id'] == me
        ? DisputeRole.seller
        : settlement?['buyer_id'] == me
        ? DisputeRole.buyer
        : null;
    if (role == null) return null;

    final dispute = DisputeModel.fromRow(row, role: role);
    return dispute.withEvidence(await _signEvidence(dispute.evidence));
  }

  /// Photo evidence is stored under its public-form URL in a private bucket,
  /// so each one is swapped for a signed URL before it can be drawn — what
  /// `signDisputeEvidenceUrls` does on web. A photo that won't sign keeps its
  /// row and simply doesn't render.
  Future<List<DisputeEvidence>> _signEvidence(
    List<DisputeEvidence> evidence,
  ) async {
    const marker = '/storage/v1/object/public/$_evidenceBucket/';
    final paths = <int, String>{};
    for (var i = 0; i < evidence.length; i++) {
      final url = evidence[i].url;
      if (evidence[i].type != 'photo' || url == null) continue;
      final at = url.indexOf(marker);
      if (at >= 0) paths[i] = url.substring(at + marker.length).split('?')[0];
    }
    if (paths.isEmpty) return evidence;

    final signedByPath = <String, String>{};
    try {
      final results = await _client.storage
          .from(_evidenceBucket)
          .createSignedUrlsResult(paths.values.toSet().toList(), 60 * 60);
      for (final result in results) {
        if (result is SignedUrlSuccess) {
          signedByPath[result.path] = result.signedUrl;
        }
      }
    } on StorageException {
      // Leave them unsigned: the statement still reads without its photos.
    }
    return [
      for (var i = 0; i < evidence.length; i++)
        evidence[i].type == 'photo'
            ? evidence[i].withUrl(signedByPath[paths[i]])
            : evidence[i],
    ];
  }

  /// The other unresolved disputes in [dispute]'s package — web's
  /// `fetchSiblingDisputesByOrder`, so one complaint about a package doesn't
  /// hide the rest.
  Future<List<SiblingDispute>> fetchSiblings(DisputeModel dispute) async {
    final orderId = dispute.item?.orderId;
    if (orderId == null) return const [];

    final rows = await _client
        .from('disputes')
        .select(
          'slug, order_items!inner(order_id, order_number, cards(name_id))',
        )
        .eq('order_items.order_id', orderId)
        .not('current_status', 'in', '(resolved,closed)')
        .neq('slug', dispute.slug)
        .order('opened_at');
    return [
      for (final row in rows)
        if (embeddedRow(row['order_items']) case final item?)
          SiblingDispute(
            slug: row['slug'] as String? ?? '',
            cardName:
                embeddedRow(item['cards'])?['name_id'] as String? ?? 'Kartu',
            orderNumber: item['order_number'] as String? ?? '',
          ),
    ];
  }

  // ── Buyer ───────────────────────────────────────────────────────────────

  /// `respond-partial-refund` — accept or turn down the seller's offer.
  Future<String?> respondPartialRefund(int disputeId, {required bool accept}) =>
      _post('/api/disputes/$disputeId/respond-partial-refund', {
        'decision': accept ? 'accept' : 'reject',
      });

  /// `approve-return` / `reject-return` — the buyer's answer to a return
  /// request.
  Future<String?> answerReturnRequest(int disputeId, {required bool approve}) =>
      _post(
        '/api/disputes/$disputeId/${approve ? 'approve' : 'reject'}-return',
      );

  Future<String?> submitReturnTracking(
    int disputeId, {
    required String courier,
    required String tracking,
  }) => _post('/api/disputes/$disputeId/submit-return-tracking', {
    'courier': courier,
    'tracking': tracking,
  });

  /// `withdraw-dispute` — drops the complaint and lets the order carry on.
  Future<String?> withdraw(String orderItemSlug) =>
      _post('/api/order-items/$orderItemSlug/withdraw-dispute');

  // ── Seller ──────────────────────────────────────────────────────────────

  Future<String?> fullRefund(int disputeId) =>
      _post('/api/disputes/$disputeId/full-refund');

  Future<String?> proposePartialRefund(int disputeId, int amount) => _post(
    '/api/disputes/$disputeId/propose-partial-refund',
    {'amount': amount},
  );

  Future<String?> requestReturn(int disputeId) =>
      _post('/api/disputes/$disputeId/request-return');

  Future<String?> refundShortfall(int disputeId) =>
      _post('/api/disputes/$disputeId/refund-shortfall');

  Future<String?> confirmReturnReceived(int disputeId) =>
      _post('/api/disputes/$disputeId/confirm-return-received');

  // ── Either side ─────────────────────────────────────────────────────────

  Future<String?> escalate(int disputeId) =>
      _post('/api/disputes/$disputeId/escalate');

  /// `POST /api/settlements/[slug]/dispute-response` — a statement plus up
  /// to four photos, which web's `DisputeResponseForm` sends.
  ///
  /// The route takes bare object paths under the settlement's own folder,
  /// so the photos go up first, there.
  Future<String?> respond(
    String settlementSlug, {
    required String statement,
    List<DisputeEvidencePhoto> photos = const [],
  }) async {
    final paths = <String>[];
    try {
      final bucket = _client.storage.from(_evidenceBucket);
      final random = Random();
      for (final photo in photos) {
        final path =
            '$settlementSlug/${DateTime.now().millisecondsSinceEpoch}-'
            '${random.nextInt(1 << 30).toRadixString(36)}.${photo.extension}';
        await bucket.uploadBinary(
          path,
          photo.bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: photo.contentType,
          ),
        );
        paths.add(path);
      }
    } on StorageException {
      await _removeUploaded(paths);
      return 'Gagal mengunggah foto';
    }

    final error = await _post(
      '/api/settlements/$settlementSlug/dispute-response',
      {'statement': statement, 'photoUrls': paths},
    );
    // A refused response leaves nothing pointing at the photos.
    if (error != null) await _removeUploaded(paths);
    return error;
  }

  Future<void> _removeUploaded(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(_evidenceBucket).remove(paths);
    } on StorageException {
      // Orphans are harmless; web leaves them too when a remove fails.
    }
  }

  /// Null on `{ ok: true }`, otherwise the route's own sentence.
  Future<String?> _post(
    String path, [
    Map<String, dynamic> body = const {},
  ]) async {
    try {
      final response = await _api.post(path, body);
      if (response['ok'] == true) return null;
      return response['error'] as String? ?? 'Terjadi kesalahan';
    } on ApiException catch (e) {
      return userFacingError(e);
    }
  }
}
