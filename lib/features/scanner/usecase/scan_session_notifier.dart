import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../expansions/repository/models/market_models.dart';
import '../repository/models/scan_models.dart';
import '../repository/scanner_repository.dart';

/// Ports `features/scanner/store/scan-session.tsx`.
///
/// The running batch of scanned cards — the "cart" the scanner fills and the
/// review list both read from. Persisted so a session survives the app being
/// backgrounded mid-binder, the same reason the web keeps it in
/// `localStorage`.

const _storageKey = 'pokepedia.scan-session.v1';

/// Ceiling on distinct rows. Ports `MAX_ITEMS`.
const _maxItems = 100;

/// Per-row quantity ceiling. Not arbitrary: it matches the limit every
/// `listing_drafts`/`listings` quantity column enforces, so a heavily
/// duplicated scan can't silently fail "Jadikan draft jual" later.
const _maxQuantity = 99;

/// One row of the scan session.
@immutable
class ScanSessionItem {
  const ScanSessionItem({
    required this.tempId,
    required this.card,
    required this.variants,
    required this.needsReview,
    required this.quantity,
    required this.logId,
  });

  final String tempId;
  final ScanCard card;

  /// Other printings sharing this card's artwork, for the variant strip.
  final List<ScanCard> variants;

  /// The match wasn't confident, so a human should look at it. Drives the
  /// review badge and sorts the row to the top of the session list.
  final bool needsReview;

  final int quantity;

  /// This scan's `recognition_logs` row, so a variant correction can be
  /// attributed back to it.
  final int? logId;

  ScanSessionItem copyWith({
    ScanCard? card,
    List<ScanCard>? variants,
    bool? needsReview,
    int? quantity,
  }) => ScanSessionItem(
    tempId: tempId,
    card: card ?? this.card,
    variants: variants ?? this.variants,
    needsReview: needsReview ?? this.needsReview,
    quantity: quantity ?? this.quantity,
    logId: logId,
  );

  Map<String, dynamic> toJson() => {
    'tempId': tempId,
    'card': card.toJson(),
    'variants': variants.map((v) => v.toJson()).toList(),
    'needsReview': needsReview,
    'quantity': quantity,
    'logId': logId,
  };

  /// Returns null for a row that can't be decoded rather than throwing.
  ///
  /// Persisted state outlives any given build, so a shape change or a
  /// corrupted entry would otherwise reach the UI as a cast that can't fail —
  /// and a stale session must never make the scanner unopenable.
  static ScanSessionItem? tryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    try {
      final card = raw['card'];
      final tempId = raw['tempId'];
      final quantity = (raw['quantity'] as num?)?.toInt();
      if (card is! Map<String, dynamic> ||
          tempId is! String ||
          quantity == null ||
          quantity < 1) {
        return null;
      }
      return ScanSessionItem(
        tempId: tempId,
        card: ScanCard.fromJson(card),
        variants: (raw['variants'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ScanCard.fromJson)
            .toList(),
        needsReview: raw['needsReview'] as bool? ?? false,
        quantity: quantity,
        logId: (raw['logId'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

class ScanSessionNotifier extends Notifier<List<ScanSessionItem>> {
  var _hydrated = false;
  var _counter = 0;

  @override
  List<ScanSessionItem> build() {
    // Hydration is async, so the first frame renders the empty session and the
    // stored one lands a moment later — the same order the web's
    // mount-time `localStorage` read produces.
    unawaited(_hydrate());
    return const [];
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final items = decoded
          .map(ScanSessionItem.tryFromJson)
          .whereType<ScanSessionItem>()
          .toList();
      state = _mergeDuplicates(items);
    } catch (e) {
      if (kDebugMode) debugPrint('[scan] session hydrate failed: $e');
    } finally {
      // Set even on failure: without it the first mutation would never
      // persist, silently disabling the feature this method exists for.
      _hydrated = true;
    }
  }

  Future<void> _persist() async {
    if (!_hydrated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(state.map((it) => it.toJson()).toList()),
      );
    } catch (e) {
      // Losing persistence is survivable; losing the in-memory session isn't.
      if (kDebugMode) debugPrint('[scan] session persist failed: $e');
    }
  }

  void _set(List<ScanSessionItem> next) {
    state = next;
    unawaited(_persist());
  }

  /// Same `card.id` collapses into one row, summing quantity; the
  /// first-scanned row wins every other field. Ports `mergeDuplicates`.
  static List<ScanSessionItem> _mergeDuplicates(List<ScanSessionItem> items) {
    final merged = <ScanSessionItem>[];
    final indexByCardId = <int, int>{};
    for (final item in items) {
      final existing = indexByCardId[item.card.id];
      if (existing == null) {
        indexByCardId[item.card.id] = merged.length;
        merged.add(item);
      } else {
        merged[existing] = merged[existing].copyWith(
          quantity: min(
            _maxQuantity,
            merged[existing].quantity + item.quantity,
          ),
        );
      }
    }
    return merged;
  }

  /// Unique enough for a key that never leaves the device — a counter plus the
  /// clock, so two rows added in the same millisecond still differ.
  String _nextTempId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  /// Records a scan. Returns the row's `tempId` so the caller can focus it.
  ///
  /// `card.id` is already variant-qualified in the catalog, so re-scanning the
  /// same physical card bumps quantity instead of adding a second row.
  String addItem({
    required ScanCard card,
    required List<ScanCard> variants,
    required bool needsReview,
    required int? logId,
  }) {
    final existingIndex = state.indexWhere((it) => it.card.id == card.id);
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      _set([
        for (final it in state)
          if (it.tempId == existing.tempId)
            it.copyWith(quantity: min(_maxQuantity, it.quantity + 1))
          else
            it,
      ]);
      return existing.tempId;
    }

    final tempId = _nextTempId();
    final next = [
      ...state,
      ScanSessionItem(
        tempId: tempId,
        card: card,
        variants: variants,
        needsReview: needsReview,
        quantity: 1,
        logId: logId,
      ),
    ];
    // Oldest rows drop first once the cap is hit, matching the web's
    // `.slice(-MAX_ITEMS)`.
    _set(
      next.length > _maxItems ? next.sublist(next.length - _maxItems) : next,
    );
    return tempId;
  }

  /// Applies a variant-strip pick. Clears [ScanSessionItem.needsReview] — the
  /// user has now personally confirmed which card this is.
  ///
  /// A switch that collides with another row merges into the edited row, so
  /// picking variant B for a card already scanned as B doesn't leave two rows
  /// for one printing.
  void setCard(String tempId, ScanCard card, List<ScanCard> variants) {
    final duplicateIndex = state.indexWhere(
      (it) => it.tempId != tempId && it.card.id == card.id,
    );
    final duplicate = duplicateIndex >= 0 ? state[duplicateIndex] : null;

    final next = <ScanSessionItem>[];
    for (final it in state) {
      // Dropped; its quantity is folded into the edited row instead.
      if (duplicate != null && it.tempId == duplicate.tempId) continue;
      next.add(
        it.tempId == tempId
            ? it.copyWith(
                card: card,
                variants: variants,
                needsReview: false,
                quantity: min(
                  _maxQuantity,
                  it.quantity + (duplicate?.quantity ?? 0),
                ),
              )
            : it,
      );
    }
    _set(next);
  }

  void setQuantity(String tempId, int quantity) {
    _set([
      for (final it in state)
        if (it.tempId == tempId)
          it.copyWith(quantity: quantity.clamp(1, _maxQuantity))
        else
          it,
    ]);
  }

  void removeItem(String tempId) =>
      _set(state.where((it) => it.tempId != tempId).toList());

  /// Batched sibling of [removeItem] — one state update and one persist write
  /// instead of N, which matters after a whole batch is drafted at once.
  void removeItems(Iterable<String> tempIds) {
    final toRemove = tempIds.toSet();
    _set(state.where((it) => !toRemove.contains(it.tempId)).toList());
  }

  void clear() => _set(const []);
}

final scanSessionProvider =
    NotifierProvider<ScanSessionNotifier, List<ScanSessionItem>>(
      ScanSessionNotifier.new,
    );

/// Total physical cards in the session (quantities summed), for the running
/// counter on the scan overlay.
final scanSessionCountProvider = Provider<int>(
  (ref) => ref
      .watch(scanSessionProvider)
      .fold(0, (sum, item) => sum + item.quantity),
);

/// Market prices for everything in the session.
///
/// Watches the session, so a newly scanned card pulls its own price in without
/// any call site remembering to ask.
final scanSessionPricesProvider = FutureProvider<Map<int, CardMarketPrice>>((
  ref,
) async {
  final session = ref.watch(scanSessionProvider);
  final ids = session.map((it) => it.card.id).toSet();
  if (ids.isEmpty) return const {};

  final repository = ref.read(scannerRepositoryProvider);
  final started = DateTime.now();
  final prices = await repository.fetchPrices(ids.toList()..sort());
  final elapsed = DateTime.now().difference(started).inMilliseconds;

  // Attributed to the newest scan, which is what triggered this refetch — the
  // provider re-runs when a card is added, so the last item is the one whose
  // perceived latency this measures. Fire-and-forget inside the repository.
  final logId = session.lastOrNull?.logId;
  if (logId != null) {
    unawaited(repository.traceScan(logId: logId, priceFetchMs: elapsed));
  }
  return prices;
});
