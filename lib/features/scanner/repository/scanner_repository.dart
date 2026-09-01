import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../expansions/repository/models/market_models.dart';
import 'models/scan_models.dart';

/// Everything the scanner talks to.
///
/// Two different transports on purpose, matching how the web splits the same
/// work:
///
///  * **`/api/scan` and `/api/scan/confirm` go through [PokepediaApi]** —
///    recognition needs `EMBEDDER_SECRET`, which only the Next.js server
///    holds, so this leg cannot be a direct Supabase call however much cheaper
///    that would be.
///  * **Everything else goes straight to Supabase** — prices, catalog search
///    and both terminal actions are plain RLS-scoped calls the app is already
///    allowed to make, so routing them through the web server would only add a
///    hop. Notably `import_listing_drafts_from_scan` is `SECURITY DEFINER`
///    with `GRANT EXECUTE … TO authenticated` and asserts `auth.uid() =
///    p_user_id` itself, so calling it directly is exactly as safe as the
///    web's `/api/seller/listing-drafts/import` wrapper around it.
class ScannerRepository {
  ScannerRepository(this._api, this._client);

  final PokepediaApi _api;
  final SupabaseClient _client;

  /// Comfortably above `/api/scan`'s own `maxDuration = 60`, so the server's
  /// mapped error always wins the race and the user sees "server sibuk"
  /// rather than a generic client timeout. Mirrors the web's
  /// `SCAN_REQUEST_TIMEOUT_MS`.
  static const _scanTimeout = Duration(seconds: 65);

  /// Sends one captured card crop for recognition.
  ///
  /// [imageBytes] must already be a tight, perspective-plausible crop at
  /// [cardAspect] — the embedder runs **no** server-side detection
  /// (`detection_source: "disabled"`), so whatever arrives here is compared
  /// against catalog renders as-is.
  ///
  /// [captureMeta] is diagnostics only: it lands in `recognition_logs` and is
  /// never used for ranking. Sent anyway because it's what makes a bad scan
  /// debuggable after the fact instead of only reproducible live.
  Future<ScanResponse> scan({
    required Uint8List imageBytes,
    required CardLanguage language,
    Map<String, dynamic>? captureMeta,
  }) async {
    final json = await _api.postMultipart(
      '/api/scan',
      fields: {
        'language': language.raw,
        if (captureMeta != null) 'camera': jsonEncode(captureMeta),
      },
      files: [
        ApiMultipartFile(
          field: 'image',
          filename: 'card.jpg',
          bytes: imageBytes,
          // JPEG rather than the web's WebP: the `image` package can't encode
          // WebP, and `/api/scan` accepts jpeg/png/webp equally. The server
          // re-encodes to WebP before the embedder sees it either way.
          contentType: 'image/jpeg',
        ),
      ],
      timeout: _scanTimeout,
    );
    return ScanResponse.fromJson(json);
  }

  /// Reports which card the user actually settled on, against this scan's own
  /// `recognition_logs` row.
  ///
  /// Fire-and-forget by design — this is accuracy telemetry, and failing the
  /// user's variant pick because a logging write didn't land would be
  /// backwards. Ports `useConfirmScanChoice`'s bare `.catch(() => {})`.
  Future<void> confirmChoice({
    required int logId,
    required int chosenCardId,
  }) async {
    try {
      await _api.post('/api/scan/confirm', {
        'logId': logId,
        'chosenCardId': chosenCardId,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[scan] confirm failed (ignored): $e');
    }
  }

  /// Market price for a batch of scanned cards, via the same
  /// `get_card_prices_by_ids` RPC the card detail page uses.
  ///
  /// Called straight from the app rather than through `/api/scan` because the
  /// web does the same — its scan timing deliberately ends when the match
  /// returns, so price never delays showing the card.
  Future<Map<int, CardMarketPrice>> fetchPrices(List<int> cardIds) async {
    if (cardIds.isEmpty) return const {};
    try {
      final rows = await _client.rpc(
        'get_card_prices_by_ids',
        params: {'p_card_ids': cardIds},
      );
      final prices = <int, CardMarketPrice>{};
      for (final row in (rows as List).whereType<Map<String, dynamic>>()) {
        final id = (row['card_id'] as num?)?.toInt();
        if (id != null) prices[id] = CardMarketPrice.fromRow(row);
      }
      return prices;
    } on PostgrestException catch (e) {
      // A missing price is a dash in the UI, never a failed scan.
      if (kDebugMode) debugPrint('[scan] price fetch failed: ${e.message}');
      return const {};
    }
  }

  /// Full-catalog fallback for "Ganti Kartu" — when recognition got the card
  /// wrong entirely, not just the printing.
  ///
  /// Scoped to one language, like the web's `ScanCardSearchSheet`: the
  /// session's language toggle is authoritative for print language, so a
  /// correction here shouldn't be able to silently reassign it.
  Future<List<ScanCard>> searchCards({
    required String query,
    CardLanguage? language,
    int limit = 40,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final rows = await _client.rpc(
        'search_cards_picker',
        params: {
          'search_query': trimmed,
          'p_limit': limit,
          'p_languages': language == null ? null : [language.raw],
        },
      );
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          // RETURNS TABLE(card jsonb) — the row wraps the catalog row.
          .map((row) => row['card'])
          .whereType<Map<String, dynamic>>()
          .map(ScanCard.fromJson)
          .toList();
    } on PostgrestException catch (e) {
      if (kDebugMode) debugPrint('[scan] card search failed: ${e.message}');
      return const [];
    }
  }

  /// Turns the selected scan batch into draft listings.
  ///
  /// Returns the card ids that actually became drafts — the RPC skips
  /// trading-blocked and already-listed cards, and the caller leaves those in
  /// the session so they stay available via "Tambah ke koleksi" instead.
  /// Ports `sendToDraftListings`, minus the web route that only wrapped this.
  Future<({List<int> insertedCardIds, String? error})> importDraftListings({
    required String userId,
    required Map<int, int> quantityByCardId,
  }) async {
    if (quantityByCardId.isEmpty) {
      return (insertedCardIds: <int>[], error: null);
    }
    try {
      final rows = await _client.rpc(
        'import_listing_drafts_from_scan',
        params: {
          'p_user_id': userId,
          'p_items': quantityByCardId.entries
              .map((e) => {'card_id': e.key, 'quantity': e.value})
              .toList(),
        },
      );
      final inserted = (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((row) => (row['inserted_card_id'] as num?)?.toInt())
          .whereType<int>()
          .toList();
      return (insertedCardIds: inserted, error: null);
    } on PostgrestException catch (e) {
      if (kDebugMode) debugPrint('[scan] draft import failed: ${e.message}');
      return (
        insertedCardIds: <int>[],
        error: 'Gagal menjadikan hasil pindai sebagai draft, coba lagi',
      );
    }
  }
}

final scannerRepositoryProvider = Provider(
  (ref) => ScannerRepository(
    ref.watch(pokepediaApiProvider),
    ref.watch(supabaseClientProvider),
  ),
);
