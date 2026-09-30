import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/card_model.dart';
import '../../../shared/models/deck_model.dart';
import '../../../shared/utils/card_pricing.dart';
import '../../../shared/utils/primary_collection.dart';
import 'models/deck_card_entry.dart';
import 'models/inventory_entry.dart';
import 'models/wantlist_model.dart';
import '../../../core/errors/user_message.dart';

const _deckSelect =
    'id, name, description, share_code, created_at, updated_at, deck_cards(quantity)';

/// The `cards` fields `CardModel.fromRow` reads — mirrors the same column
/// list in `ExpansionsRepository`.
const _cardColumns =
    'id, name_id, expansion_code, collector_number, rarity, category, image_url, illustrator, regulation_mark, language, variant, details';

/// Mirrors the `collections` columns the web's collection API selects.
/// `slug` replaces the old `share_code`: sharing is a public URL now, and the
/// slug is minted by `trg_set_collection_slug` rather than by the client.
const _listColumns =
    'id, name, description, slug, is_public, created_at, updated_at, collection_cards(count)';

/// `collections_name_len` / `collections_description_len` — the CHECK
/// constraints the table enforces, mirrored here so the sheet can say so
/// before the round trip.
const listNameMaxLength = 100;
const listDescriptionMaxLength = 500;

/// Nine characters from an alphabet with the ambiguous glyphs (I, l, O, 0, 1)
/// left out, hyphenated in the middle.
///
/// Decks only, now that collections share by slug — `decks.share_code` is
/// untouched by the collections unification.
String generateShareCode() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 9; i++) {
    if (i == 4) buffer.write('-');
    buffer.write(chars[random.nextInt(chars.length)]);
  }
  return buffer.toString();
}

/// Data access for the Portfolio feature (Koleksi / Deck / Inventori /
/// Wishlist tabs), backed by Supabase. Mirrors `fetchCollectionCards` /
/// `fetchUserDecks` / `lib/products/wishlist.ts` / the web's collection API.
/// How many cards a collection may carry into the app.
///
/// PostgREST answers at most a page at a time — Supabase's "Max rows" is
/// 1000 by default — and a query with no `range` silently stops there rather
/// than erroring. That is why a 8,495-card collection reported "1000 kartu
/// unik": not a chart limit, a truncated read that every total downstream
/// then agreed on.
const maxCollectionRows = 15000;

/// One page of a PostgREST read.
const _collectionPageSize = 1000;

/// Reads every row [page] describes, a page at a time, up to [max].
///
/// Client-side paging rather than a bigger `limit`: the server cap wins over
/// whatever the client asks for, so the only way past it is to ask again.
Future<List<Map<String, dynamic>>> _pagedRows(
  Future<dynamic> Function(int from, int to) page, {
  int max = maxCollectionRows,
}) async {
  final all = <Map<String, dynamic>>[];
  for (var from = 0; from < max; from += _collectionPageSize) {
    final to = min(from + _collectionPageSize, max) - 1;
    final rows = await page(from, to);
    if (rows is! List || rows.isEmpty) break;
    all.addAll(rows.cast<Map<String, dynamic>>());
    // A short page is the last page — asking again would spend a round trip
    // to be told the same thing.
    if (rows.length < to - from + 1) break;
  }
  return all;
}

class PortfolioRepository {
  PortfolioRepository(this._client);

  final SupabaseClient _client;

  /// Owned cards — the primary collection's rows, joined with `cards`.
  ///
  /// This is what `user_cards` became: the same pile, now one collection
  /// among several, distinguished by `collections.is_primary`.
  Future<List<CardModel>> fetchCollection(String userId) async {
    final collectionId = await primaryCollectionId(_client, userId);
    if (collectionId == null) return const [];
    final rows = await _pagedRows(
      (from, to) => _client
          .from('collection_cards')
          .select('quantity, cards!inner($_cardColumns)')
          .eq('collection_id', collectionId)
          .gt('quantity', 0)
          // Ordered, because paging without one lets the server return the
          // same row twice across two pages and drop another entirely.
          .order('card_id', ascending: true)
          .range(from, to),
    );
    final cards = rows.map((r) {
      final card = CardModel.fromRow(r['cards'] as Map<String, dynamic>);
      return card.copyWith(owned: r['quantity'] as int);
    }).toList();
    // `cards` carries no price, so an unpriced collection made every tile
    // blank and every total zero. One batch call covers the whole thing.
    return priceCards(_client, cards);
  }

  /// Ports `fetchUserDecks` (`lib/products/decks.ts`) — card count is the
  /// sum of the joined `deck_cards.quantity` rows.
  Future<List<DeckModel>> fetchDecks(String userId) async {
    final rows = await _client
        .from('decks')
        .select(_deckSelect)
        .eq('user_id', userId)
        .order('updated_at', ascending: false);
    return rows.map(_mapDeckRow).toList();
  }

  DeckModel _mapDeckRow(Map<String, dynamic> r) {
    final deckCards = (r['deck_cards'] as List).cast<Map<String, dynamic>>();
    final cardCount = deckCards.fold<int>(
      0,
      (sum, dc) => sum + (dc['quantity'] as int? ?? 0),
    );
    return DeckModel(
      id: r['id'] as String,
      name: r['name'] as String,
      description: r['description'] as String? ?? '',
      shareCode: r['share_code'] as String,
      cardCount: cardCount,
      createdAt: r['created_at'] as String,
      updatedAt: r['updated_at'] as String,
    );
  }

  /// Ports `createDeck` — retries on a share-code collision (unique
  /// constraint), same as the web.
  Future<({DeckModel? deck, String? error})> createDeck({
    required String userId,
    required String name,
    String description = '',
  }) async {
    const maxRetries = 3;
    for (var i = 0; i < maxRetries; i++) {
      try {
        final row = await _client
            .from('decks')
            .insert({
              'user_id': userId,
              'name': name,
              'description': description,
              'share_code': generateShareCode(),
            })
            .select(_deckSelect)
            .single();
        return (deck: _mapDeckRow(row), error: null);
      } on PostgrestException catch (e) {
        if (e.code == '23505' && i < maxRetries - 1) continue;
        return (deck: null, error: userFacingError(e));
      }
    }
    return (deck: null, error: 'Gagal membuat kode berbagi yang unik');
  }

  Future<String?> updateDeck({
    required String deckId,
    required String userId,
    required String name,
    required String description,
  }) async {
    try {
      await _client
          .from('decks')
          .update({'name': name, 'description': description})
          .eq('id', deckId)
          .eq('user_id', userId);
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  Future<String?> deleteDeck({
    required String deckId,
    required String userId,
  }) async {
    try {
      await _client
          .from('decks')
          .delete()
          .eq('id', deckId)
          .eq('user_id', userId);
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  Future<({DeckModel? deck, String? error})> duplicateDeck(
    String sourceDeckId,
  ) async {
    try {
      final newId =
          await _client.rpc(
                'duplicate_deck',
                params: {'p_source_deck_id': sourceDeckId},
              )
              as String;
      final row = await _client
          .from('decks')
          .select(_deckSelect)
          .eq('id', newId)
          .single();
      return (deck: _mapDeckRow(row), error: null);
    } on PostgrestException catch (e) {
      return (deck: null, error: userFacingError(e));
    }
  }

  Future<List<DeckCardEntry>> fetchDeckCards(String deckId) async {
    final rows = await _client
        .from('deck_cards')
        .select('quantity, cards!inner($_cardColumns)')
        .eq('deck_id', deckId);
    return rows.map((r) {
      final card = CardModel.fromRow(r['cards'] as Map<String, dynamic>);
      return DeckCardEntry(
        card: card,
        quantity: r['quantity'] as int,
        category: _toDeckCategory(card.category),
      );
    }).toList();
  }

  DeckCategory _toDeckCategory(CardCategory category) => switch (category) {
    CardCategory.pokemon => DeckCategory.pokemon,
    CardCategory.trainer => DeckCategory.trainer,
    CardCategory.energy => DeckCategory.energy,
  };

  /// Ports `upsertDeckCard` — the `upsert_deck_card` RPC already enforces
  /// the 60-card/4-copy/1-ACE rules server-side (deleting the row if the
  /// resulting quantity is <= 0), so the client just needs to surface
  /// whatever error it raises.
  Future<String?> upsertDeckCard({
    required String deckId,
    required int cardId,
    required int delta,
  }) async {
    try {
      await _client.rpc(
        'upsert_deck_card',
        params: {'p_deck_id': deckId, 'p_card_id': cardId, 'p_delta': delta},
      );
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  /// Ports the "wishlist" card-heart feature (`hooks/useWishlist.ts` +
  /// `card_wishlists` table) — cards a user has starred from anywhere in
  /// the catalog, independent of what they actually own.
  ///
  /// `card_wishlists` has RLS enabled with *no* policies defined, so it
  /// can't be queried directly from the client (every direct `SELECT`
  /// silently returns zero rows — not an error). The web never does this
  /// either: reads/writes only ever go through `get_my_wishlist` /
  /// `add_card_wishlist` / `remove_card_wishlist`, which are all
  /// `SECURITY DEFINER` and bypass RLS. `fetchWishlistedCardIds` is the
  /// single source of truth both `fetchWishlist` and the per-card
  /// "is this wishlisted" check derive from — mirrors `useWishlist()`
  /// fetching the full id set once and checking membership client-side.
  Future<Set<int>> fetchWishlistedCardIds() async {
    final rows = await _client.rpc('get_my_wishlist') as List;
    return rows.map((r) => r['card_id'] as int).toSet();
  }

  Future<List<CardModel>> fetchWishlist(String userId) async {
    final cardIds = await fetchWishlistedCardIds();
    if (cardIds.isEmpty) return const [];
    final rows = await _client
        .from('cards')
        .select(_cardColumns)
        .inFilter('id', cardIds.toList())
        .range(0, maxCollectionRows - 1);
    // The wishlist draws the same tiles as the collection, so it prices the
    // same way — otherwise half the app's cards show a value and half don't.
    return priceCards(_client, rows.map(CardModel.fromRow).toList());
  }

  /// Ports `add_card_wishlist`/`remove_card_wishlist` — same RPCs
  /// `components/card/wishlist-button.tsx` calls.
  Future<String?> setWishlisted(int cardId, bool wishlisted) async {
    try {
      await _client.rpc(
        wishlisted ? 'add_card_wishlist' : 'remove_card_wishlist',
        params: {'p_card_id': cardId},
      );
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  static const _inventorySelect =
      'id, card_id, quantity, unit_price, created_at, notes, cards!inner($_cardColumns)';

  InventoryEntry _mapInventoryRow(Map<String, dynamic> r) => InventoryEntry(
    id: r['id'] as int,
    card: CardModel.fromRow(r['cards'] as Map<String, dynamic>),
    quantity: r['quantity'] as int,
    unitPrice: r['unit_price'] as int,
    createdAt: DateTime.parse(r['created_at'] as String),
    notes: r['notes'] as String?,
  );

  /// Ports `fetchInventoryRecords` — confirmed (non-draft) `user_inventory`
  /// rows. This is the "Database" view: what's actually in the inventory.
  Future<List<InventoryEntry>> fetchInventoryRecords(String userId) async {
    final rows = await _client
        .from('user_inventory')
        .select(_inventorySelect)
        .eq('user_id', userId)
        .eq('is_draft', false)
        .order('created_at', ascending: false);
    return rows.map(_mapInventoryRow).toList();
  }

  /// Ports `fetchDraftRecords` — rows staged via "Tambahkan" but not yet
  /// confirmed into the collection.
  Future<List<InventoryEntry>> fetchDraftRecords(String userId) async {
    final rows = await _client
        .from('user_inventory')
        .select(_inventorySelect)
        .eq('user_id', userId)
        .eq('is_draft', true)
        .order('created_at', ascending: false);
    return rows.map(_mapInventoryRow).toList();
  }

  /// Ports `createDraftRecord`.
  Future<({int? id, String? error})> createDraftRecord({
    required String userId,
    required int cardId,
    required int quantity,
    required int unitPrice,
  }) async {
    try {
      final row = await _client
          .from('user_inventory')
          .insert({
            'user_id': userId,
            'card_id': cardId,
            'quantity': quantity,
            'unit_price': unitPrice,
            'is_draft': true,
            'source': 'search',
          })
          .select('id')
          .single();
      return (id: row['id'] as int, error: null);
    } on PostgrestException catch (e) {
      return (id: null, error: userFacingError(e));
    }
  }

  Future<String?> updateDraftRecord({
    required String userId,
    required int recordId,
    required int quantity,
    required int unitPrice,
    String? notes,
  }) async {
    try {
      await _client
          .from('user_inventory')
          .update({
            'quantity': quantity,
            'unit_price': unitPrice,
            // Only when the caller is editing it: the draft table writes a
            // note per row, the add sheet doesn't touch one.
            if (notes != null) 'notes': notes.isEmpty ? null : notes,
          })
          .eq('id', recordId)
          .eq('user_id', userId)
          .eq('is_draft', true);
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  Future<String?> deleteDraftRecord({
    required String userId,
    required int recordId,
  }) async {
    try {
      await _client
          .from('user_inventory')
          .delete()
          .eq('id', recordId)
          .eq('user_id', userId)
          .eq('is_draft', true);
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  /// Ports `confirmDraftRecord` — flips a draft to confirmed. Doesn't touch
  /// the collection itself (mirrors the web, which separately calls
  /// `upsertCollectionCard` afterward); callers should follow up with
  /// `ExpansionsRepository.upsertUserCard`.
  Future<String?> confirmDraftRecord({
    required String userId,
    required int recordId,
    required int quantity,
    required int unitPrice,
  }) async {
    try {
      await _client.rpc(
        'confirm_inventory_draft',
        params: {
          'p_user_id': userId,
          'p_record_id': recordId,
          'p_quantity': quantity,
          'p_unit_price': unitPrice,
        },
      );
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  /// Ports `fetchInventoryActivity` — a read-only audit trail.
  Future<List<InventoryActivityEntry>> fetchInventoryActivity(
    String userId,
  ) async {
    final rows = await _client
        .from('user_inventory_activity')
        .select(
          'id, card_id, action, quantity, unit_price, created_at, cards!inner($_cardColumns)',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.map((r) {
      return InventoryActivityEntry(
        id: r['id'] as int,
        card: CardModel.fromRow(r['cards'] as Map<String, dynamic>),
        action: InventoryActivityActionX.fromRaw(r['action'] as String),
        quantity: r['quantity'] as int,
        unitPrice: r['unit_price'] as int,
        createdAt: DateTime.parse(r['created_at'] as String),
      );
    }).toList();
  }

  /// Ports `removeInventoryRecords` (`bulk_remove_inventory` RPC) —
  /// removes up to [items].delQty of each record, deleting the row if it
  /// hits zero. The RPC already decrements the primary collection and logs
  /// the activity row server-side, so no follow-up call is needed.
  Future<String?> bulkRemoveInventory(
    String userId,
    List<({int recordId, int delQty})> items,
  ) async {
    if (items.isEmpty) return null;
    try {
      await _client.rpc(
        'bulk_remove_inventory',
        params: {
          'p_user_id': userId,
          'p_items': items
              .map((i) => {'record_id': i.recordId, 'del_qty': i.delQty})
              .toList(),
        },
      );
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  /// Ports `searchCardsPicker` — the catalog search used by "Tambahkan" to
  /// find a card to stage into inventory.
  Future<List<CardModel>> searchCardsPicker(
    String query, {
    CardLanguage? language,
  }) async {
    if (query.trim().length < 2) return const [];
    final rows =
        await _client.rpc(
              'search_cards_picker',
              params: {
                'search_query': query,
                'p_limit': 40,
                // Narrowed in SQL rather than after the fact: the RPC
                // returns one capped page, so filtering the page here would
                // answer "Pikachu in EN" with whatever few English prints
                // happened to make the mixed-language cut.
                'p_languages': language == null ? null : [language.raw],
                'p_regulation_marks': null,
              },
            )
            as List;
    return rows
        .map(
          (r) => CardModel.fromRow(
            (r as Map<String, dynamic>)['card'] as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  /// The user's own collections, most recently touched first, with their
  /// card counts from the embedded `collection_cards(count)`.
  ///
  /// `is_primary` is excluded: that row is the main collection, drawn by the
  /// Koleksi tab through [fetchCollection], and showing it here would list it
  /// twice under two different names.
  ///
  /// `collections` and `collection_cards` are own-row under RLS ("Users can
  /// manage own collections"), so this and the reads below run on the user's
  /// own session without a server route. The writes go through the RPCs
  /// instead — see [addCopiesToList].
  Future<List<WantlistModel>> fetchLists(String userId) async {
    final rows = await _client
        .from('collections')
        .select(_listColumns)
        .eq('user_id', userId)
        .eq('is_primary', false)
        .order('updated_at', ascending: false);
    return rows.map(WantlistModel.fromRow).toList();
  }

  /// A collection's cards, in the order they were filed (`created_at`
  /// ascending) — the same order `get_public_collection_cards` returns.
  Future<List<CardModel>> fetchListCards(String listId) async {
    final rows = await _client
        .from('collection_cards')
        .select('id, quantity, notes, created_at, cards!inner($_cardColumns)')
        .eq('collection_id', listId)
        .order('created_at', ascending: true)
        // A list is a collection too, and hits the same page ceiling.
        .range(0, maxCollectionRows - 1);
    final cards = rows.map((r) {
      final card = CardModel.fromRow(r['cards'] as Map<String, dynamic>);
      // The list's own quantity, not an ownership count — the detail grid
      // reads it the same way the collection shows copies held.
      return card.copyWith(owned: (r['quantity'] as num?)?.toInt() ?? 1);
    }).toList();
    return priceCards(_client, cards);
  }

  /// Puts cards on a list's shelf at one copy each, leaving any already
  /// there at the quantity they have. Returns how many were actually new, so
  /// a caller can say what it did rather than what it asked for.
  ///
  /// Membership is read first rather than leaning on `ignoreDuplicates`:
  /// the skipped rows are exactly the difference between the two counts, and
  /// an upsert doesn't report them.
  Future<({int count, String? error})> addCardsToList({
    required String listId,
    required List<int> cardIds,
  }) async {
    if (cardIds.isEmpty) return (count: 0, error: null);
    try {
      final existing = await _client
          .from('collection_cards')
          .select('card_id')
          .eq('collection_id', listId)
          .inFilter('card_id', cardIds);
      final held = {
        for (final row in existing) (row['card_id'] as num).toInt(),
      };
      final fresh = cardIds.where((id) => !held.contains(id)).toList();
      if (fresh.isEmpty) return (count: 0, error: null);

      // Chunked at the RPC's own ceiling — it raises past 500 ids rather
      // than truncating, and a large pack can clear that on its own.
      for (var start = 0; start < fresh.length; start += _bulkCardLimit) {
        final end = start + _bulkCardLimit;
        await _client.rpc(
          'bulk_upsert_collection_cards',
          params: {
            'p_collection_id': listId,
            'p_card_ids': fresh.sublist(
              start,
              end > fresh.length ? fresh.length : end,
            ),
            'p_delta': 1,
          },
        );
      }
      return (count: fresh.length, error: null);
    } on PostgrestException catch (e) {
      return (count: 0, error: userFacingError(e));
    }
  }

  /// Stores copies of cards in a list, adding to whatever quantity is
  /// already there.
  ///
  /// Each collection holds its own cards, so this is how many copies live on
  /// that shelf.
  ///
  /// One `upsert_collection_card` call per card, rather than a table upsert:
  /// the RPC adds the delta server-side (`quantity = quantity + p_delta`), so
  /// the read-then-write race the old `list_cards` path had is gone, and when
  /// the target is the primary collection it also mirrors the change into
  /// `user_inventory` — which a direct table write silently skips.
  Future<String?> addCopiesToList({
    required String listId,
    required Map<int, int> quantityByCardId,
  }) async {
    if (quantityByCardId.isEmpty) return null;
    try {
      for (final entry in quantityByCardId.entries) {
        if (entry.value == 0) continue;
        await _client.rpc(
          'upsert_collection_card',
          params: {
            'p_collection_id': listId,
            'p_card_id': entry.key,
            'p_delta': entry.value,
          },
        );
      }
      return null;
    } on PostgrestException catch (e) {
      return _collectionError(e);
    }
  }

  /// Sets how many copies of a card the collection holds, dropping the row
  /// when that reaches zero.
  ///
  /// `upsert_collection_card` only speaks deltas, so the current quantity is
  /// read first and the difference sent. Going through the RPC rather than
  /// writing the absolute value straight to the table is what keeps the
  /// primary collection's inventory drawdown firing on a decrease; the read
  /// is the price of that.
  Future<String?> setListCardQuantity({
    required String listId,
    required int cardId,
    required int quantity,
  }) async {
    try {
      final row = await _client
          .from('collection_cards')
          .select('quantity')
          .eq('collection_id', listId)
          .eq('card_id', cardId)
          .maybeSingle();
      final current = (row?['quantity'] as num?)?.toInt() ?? 0;
      final target = quantity < 1 ? 0 : quantity;
      final delta = target - current;
      if (delta == 0) return null;

      await _client.rpc(
        'upsert_collection_card',
        params: {
          'p_collection_id': listId,
          'p_card_id': cardId,
          'p_delta': delta,
        },
      );
      return null;
    } on PostgrestException catch (e) {
      return _collectionError(e);
    }
  }

  /// Removes cards from a collection outright.
  ///
  /// For a non-primary collection the cards themselves and the user's
  /// ownership of them are untouched. On the *primary* collection
  /// `bulk_remove_collection_cards` also clears the matching `user_inventory`
  /// rows and logs an `out` activity row for each, so a caller acting on it
  /// has to revalidate inventory too.
  Future<String?> removeCardsFromList({
    required String listId,
    required List<int> cardIds,
  }) async {
    if (cardIds.isEmpty) return null;
    try {
      for (var start = 0; start < cardIds.length; start += _bulkCardLimit) {
        final end = start + _bulkCardLimit;
        await _client.rpc(
          'bulk_remove_collection_cards',
          params: {
            'p_collection_id': listId,
            'p_card_ids': cardIds.sublist(
              start,
              end > cardIds.length ? cardIds.length : end,
            ),
          },
        );
      }
      return null;
    } on PostgrestException catch (e) {
      return _collectionError(e);
    }
  }

  /// Creates a collection.
  ///
  /// No share code and no retry loop any more: `collections` has no such
  /// column, and its `slug` — the handle the public URL uses — is minted by
  /// `trg_set_collection_slug`, which resolves its own collisions per user
  /// under an advisory lock. The client sends a name and nothing else.
  Future<({WantlistModel? list, String? error})> createList({
    required String userId,
    required String name,
    String description = '',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return (list: null, error: 'Nama list wajib diisi');
    if (trimmed.length > listNameMaxLength) {
      return (list: null, error: 'Nama list terlalu panjang');
    }
    if (description.length > listDescriptionMaxLength) {
      return (list: null, error: 'Deskripsi terlalu panjang');
    }

    try {
      final row = await _client
          .from('collections')
          .insert({
            'user_id': userId,
            'name': trimmed,
            'description': description.trim(),
          })
          .select(_listColumns)
          .single();
      return (list: WantlistModel.fromRow(row), error: null);
    } on PostgrestException catch (e) {
      return (list: null, error: _collectionError(e));
    }
  }

  /// Renames a collection. A rename re-points its public URL by design —
  /// `trg_set_collection_slug` fires on `UPDATE OF name` and the old slug
  /// stops resolving.
  Future<String?> updateList({
    required String listId,
    required String userId,
    required String name,
    required String description,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Nama list wajib diisi';
    if (trimmed.length > listNameMaxLength) return 'Nama list terlalu panjang';
    if (description.length > listDescriptionMaxLength) {
      return 'Deskripsi terlalu panjang';
    }
    try {
      await _client
          .from('collections')
          .update({'name': trimmed, 'description': description.trim()})
          .eq('id', listId)
          .eq('user_id', userId);
      return null;
    } on PostgrestException catch (e) {
      return _collectionError(e);
    }
  }

  /// Deletes a collection; its cards go with it on the cascade.
  ///
  /// The primary collection cannot be deleted —
  /// `trg_prevent_primary_collection_delete` raises rather than letting an
  /// account end up with nowhere to put what it owns.
  Future<String?> deleteList({
    required String listId,
    required String userId,
  }) async {
    try {
      await _client
          .from('collections')
          .delete()
          .eq('id', listId)
          .eq('user_id', userId);
      return null;
    } on PostgrestException catch (e) {
      return _collectionError(e);
    }
  }

  /// `duplicate_collection` copies the row and its cards server-side and
  /// hands back the new id. The copy is never primary, so it lands in the
  /// lists screen alongside the others.
  Future<({WantlistModel? list, String? error})> duplicateList(
    String sourceListId,
  ) async {
    try {
      final newId = await _client.rpc(
        'duplicate_collection',
        params: {'p_source_collection_id': sourceListId},
      );
      if (newId is! String || newId.isEmpty) {
        return (list: null, error: 'Respons tidak dikenali dari server');
      }
      final row = await _client
          .from('collections')
          .select(_listColumns)
          .eq('id', newId)
          .maybeSingle();
      if (row == null) {
        return (list: null, error: 'Koleksi dibuat tapi gagal dimuat');
      }
      return (list: WantlistModel.fromRow(row), error: null);
    } on PostgrestException catch (e) {
      return (list: null, error: _collectionError(e));
    }
  }

  /// The ceiling `bulk_upsert_collection_cards` enforces — it raises past
  /// this rather than truncating, so callers chunk instead of guarding.
  static const _bulkCardLimit = 500;

  /// Turns the collection functions' raised messages into something a user
  /// can read. They come back as bare Postgres exception text, which is fine
  /// in a server log and useless in a snackbar.
  static String _collectionError(PostgrestException e) => switch (e.message) {
    'Collection limit reached' => 'Jumlah koleksi sudah mencapai batas',
    'primary_collection_undeletable' => 'Koleksi utama tidak bisa dihapus',
    'is_primary_immutable' => 'Koleksi utama tidak bisa diubah',
    'unauthorized' => 'Kamu tidak punya akses ke koleksi ini',
    'delta_out_of_range' => 'Jumlah kartu di luar batas',
    _ => e.message,
  };
}
