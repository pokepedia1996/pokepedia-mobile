import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/data/dummy_catalog.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/deck_model.dart';
import 'models/deck_card_entry.dart';
import 'models/inventory_entry.dart';
import 'models/wantlist_model.dart';

const _deckSelect = 'id, name, description, share_code, created_at, updated_at, deck_cards(quantity)';

/// The `cards` fields `CardModel.fromRow` reads — mirrors the same column
/// list in `ExpansionsRepository`.
const _cardColumns =
    'id, name_id, expansion_code, collector_number, rarity, category, image_url, illustrator, regulation_mark, language, variant, details';

/// Data access for the Portfolio feature (Koleksi / Deck / Inventori /
/// Wishlist tabs), backed by Supabase. Mirrors `fetchCollectionCards` /
/// `fetchUserDecks` / `lib/products/wishlist.ts` on the web. `fetchLists`/
/// `fetchListCards` (the separate "List"/wantlist feature, not shown on
/// this tab bar) still return dummy data pending their own pass.
class PortfolioRepository {
  PortfolioRepository(this._client);

  final SupabaseClient _client;

  /// Owned cards (`user_cards.quantity > 0`), joined with their `cards` row.
  Future<List<CardModel>> fetchCollection(String userId) async {
    final rows = await _client
        .from('user_cards')
        .select('quantity, cards!inner($_cardColumns)')
        .eq('user_id', userId)
        .gt('quantity', 0);
    return rows.map((r) {
      final card = CardModel.fromRow(r['cards'] as Map<String, dynamic>);
      return card.copyWith(owned: r['quantity'] as int);
    }).toList();
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
    final cardCount = deckCards.fold<int>(0, (sum, dc) => sum + (dc['quantity'] as int? ?? 0));
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
              'share_code': _generateShareCode(),
            })
            .select(_deckSelect)
            .single();
        return (deck: _mapDeckRow(row), error: null);
      } on PostgrestException catch (e) {
        if (e.code == '23505' && i < maxRetries - 1) continue;
        return (deck: null, error: e.message);
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
      return e.message;
    }
  }

  Future<String?> deleteDeck({required String deckId, required String userId}) async {
    try {
      await _client.from('decks').delete().eq('id', deckId).eq('user_id', userId);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<({DeckModel? deck, String? error})> duplicateDeck(String sourceDeckId) async {
    try {
      final newId = await _client.rpc('duplicate_deck', params: {'p_source_deck_id': sourceDeckId}) as String;
      final row = await _client.from('decks').select(_deckSelect).eq('id', newId).single();
      return (deck: _mapDeckRow(row), error: null);
    } on PostgrestException catch (e) {
      return (deck: null, error: e.message);
    }
  }

  static const _shareCodeChars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';

  String _generateShareCode() {
    final rand = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 9; i++) {
      if (i == 4) buffer.write('-');
      buffer.write(_shareCodeChars[rand.nextInt(_shareCodeChars.length)]);
    }
    return buffer.toString();
  }

  Future<List<DeckCardEntry>> fetchDeckCards(String deckId) async {
    final rows = await _client.from('deck_cards').select('quantity, cards!inner($_cardColumns)').eq('deck_id', deckId);
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
  Future<String?> upsertDeckCard({required String deckId, required int cardId, required int delta}) async {
    try {
      await _client.rpc(
        'upsert_deck_card',
        params: {'p_deck_id': deckId, 'p_card_id': cardId, 'p_delta': delta},
      );
      return null;
    } on PostgrestException catch (e) {
      return e.message;
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
    final rows = await _client.from('cards').select(_cardColumns).inFilter('id', cardIds.toList());
    return rows.map((r) => CardModel.fromRow(r)).toList();
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
      return e.message;
    }
  }

  static const _inventorySelect = 'id, card_id, quantity, unit_price, created_at, notes, cards!inner($_cardColumns)';

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
      return (id: null, error: e.message);
    }
  }

  Future<String?> updateDraftRecord({
    required String userId,
    required int recordId,
    required int quantity,
    required int unitPrice,
  }) async {
    try {
      await _client
          .from('user_inventory')
          .update({'quantity': quantity, 'unit_price': unitPrice})
          .eq('id', recordId)
          .eq('user_id', userId)
          .eq('is_draft', true);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> deleteDraftRecord({required String userId, required int recordId}) async {
    try {
      await _client.from('user_inventory').delete().eq('id', recordId).eq('user_id', userId).eq('is_draft', true);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Ports `confirmDraftRecord` — flips a draft to confirmed. Doesn't touch
  /// `user_cards` itself (mirrors the web, which separately calls
  /// `upsertUserCard` afterward); callers should follow up with
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
      return e.message;
    }
  }

  /// Ports `fetchInventoryActivity` — a read-only audit trail.
  Future<List<InventoryActivityEntry>> fetchInventoryActivity(String userId) async {
    final rows = await _client
        .from('user_inventory_activity')
        .select('id, card_id, action, quantity, unit_price, created_at, cards!inner($_cardColumns)')
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
  /// hits zero. The RPC already decrements `user_cards` and logs the
  /// activity row server-side, so no follow-up call is needed.
  Future<String?> bulkRemoveInventory(String userId, List<({int recordId, int delQty})> items) async {
    if (items.isEmpty) return null;
    try {
      await _client.rpc(
        'bulk_remove_inventory',
        params: {
          'p_user_id': userId,
          'p_items': items.map((i) => {'record_id': i.recordId, 'del_qty': i.delQty}).toList(),
        },
      );
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Ports `searchCardsPicker` — the catalog search used by "Tambahkan" to
  /// find a card to stage into inventory.
  Future<List<CardModel>> searchCardsPicker(String query) async {
    if (query.trim().length < 2) return const [];
    final rows =
        await _client.rpc(
              'search_cards_picker',
              params: {
                'search_query': query,
                'p_limit': 20,
                'p_languages': null,
                'p_regulation_marks': null,
              },
            )
            as List;
    return rows.map((r) => CardModel.fromRow((r as Map<String, dynamic>)['card'] as Map<String, dynamic>)).toList();
  }

  Future<List<WantlistModel>> fetchLists() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return const [
      WantlistModel(id: 1, name: 'Buruan Beli', cardCount: 12, updatedAt: '1 hari lalu'),
      WantlistModel(id: 2, name: 'Grail List', cardCount: 5, updatedAt: '2 minggu lalu'),
    ];
  }

  Future<List<CardModel>> fetchListCards(int listId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return DummyCatalog.allCards.skip(listId * 5).take(listId == 1 ? 12 : 5).toList();
  }
}
