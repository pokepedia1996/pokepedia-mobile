import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/expansions/usecase/expansions_notifier.dart';
import '../../features/portfolio/usecase/portfolio_notifier.dart';
import '../../shared/models/deck_model.dart';

/// Single choke point for every mutation that changes what a user owns or
/// has wishlisted.
///
/// Riverpod's `FutureProvider`s already behave like SWR — a widget that
/// `ref.watch`s one shows the cached value immediately and only refetches
/// once told the data is stale via `ref.invalidate(...)`. The bug wasn't
/// missing caching, it was that each screen mutating ownership (card
/// detail's add/remove, the portfolio inventory stepper) only remembered
/// to invalidate the providers *it* reads, not every other screen's — so
/// e.g. adding a card from the card-detail page never told the portfolio
/// collection list to refetch.
///
/// Routing every mutation through this controller instead means adding a
/// new screen that reads ownership data never requires hunting down every
/// existing call site: it revalidates the full set of dependents in one
/// place, once, and every future call site gets that for free.
class CardOwnershipController {
  CardOwnershipController(this._ref);

  final Ref _ref;

  /// [listId] names the portfolio the caller picked. Each list is a shelf of
  /// its own, so copies filed into one stay there and the main collection —
  /// `user_cards` — is only written when the main collection is what was
  /// chosen.
  ///
  /// The destination only applies on the way in. A negative [delta] is always
  /// the main collection's, since that's the count the card-detail stepper
  /// works against; a list gives cards back through `removeCardsFromList`.
  Future<String?> adjustQuantity({
    required String userId,
    required int cardId,
    required int delta,
    String? listId,
  }) async {
    if (listId != null && delta > 0) {
      return _storeInList(listId, {cardId: delta});
    }
    final error = await _ref
        .read(expansionsRepositoryProvider)
        .upsertUserCard(userId: userId, cardId: cardId, delta: delta);
    if (error == null) _revalidateOwnership(cardId);
    return error;
  }

  /// Stores copies of several cards in one portfolio — the scanner's "add
  /// everything I just scanned" case.
  ///
  /// Returns the cards that didn't land, so a caller can keep them and let
  /// the user retry rather than losing them. A list takes the whole batch in
  /// one write, so it all lands or none of it does; the main collection is a
  /// call per card, which is the only shape `upsert_user_card` offers.
  Future<Set<int>> addCopies({
    required String userId,
    required Map<int, int> quantityByCardId,
    String? listId,
  }) async {
    if (listId != null) {
      final error = await _storeInList(listId, quantityByCardId);
      return error == null ? const {} : quantityByCardId.keys.toSet();
    }
    final failed = <int>{};
    for (final entry in quantityByCardId.entries) {
      final error = await adjustQuantity(
        userId: userId,
        cardId: entry.key,
        delta: entry.value,
      );
      if (error != null) failed.add(entry.key);
    }
    return failed;
  }

  /// Sets how many copies of a card a list holds — the list's answer to
  /// editing a quantity in the collection grid.
  Future<String?> setListCardQuantity({
    required String listId,
    required int cardId,
    required int quantity,
  }) async {
    final error = await _ref
        .read(portfolioRepositoryProvider)
        .setListCardQuantity(
          listId: listId,
          cardId: cardId,
          quantity: quantity,
        );
    if (error == null) _revalidateList(listId);
    return error;
  }

  /// Ports `handleBulkAdd` on the pack detail page — adds one copy of every
  /// card the user doesn't already own. With a [listId] the copies go to that
  /// list instead, on the same terms as [adjustQuantity].
  Future<({int count, String? error})> bulkAddToCollection({
    required String userId,
    required List<int> cardIds,
    String? listId,
  }) async {
    if (listId != null) {
      // `addCardsToList` rather than `addCopiesToList`: "add every card in
      // this pack" means make sure each one is on the shelf, not stack
      // another copy onto the ones already there.
      final result = await _ref
          .read(portfolioRepositoryProvider)
          .addCardsToList(listId: listId, cardIds: cardIds);
      if (result.error == null) _revalidateList(listId);
      return result;
    }
    final result = await _ref
        .read(expansionsRepositoryProvider)
        .bulkUpsertUserCards(userId: userId, cardIds: cardIds, delta: 1);
    // Revalidated even on a partial failure: `count` copies did land.
    _revalidateBulkOwnership(cardIds);
    return result;
  }

  Future<String?> _storeInList(
    String listId,
    Map<int, int> quantityByCardId,
  ) async {
    final error = await _ref
        .read(portfolioRepositoryProvider)
        .addCopiesToList(listId: listId, quantityByCardId: quantityByCardId);
    if (error == null) _revalidateList(listId);
    return error;
  }

  /// Refreshes what reads a list — its own card grid, and the card-count
  /// badge every list row shows.
  void _revalidateList(String listId) {
    _ref.invalidate(listCardsProvider(listId));
    _ref.invalidate(listsProvider);
  }

  /// Ports `handleBulkRemove`. `bulk_remove_user_cards` also clears the
  /// matching `user_inventory` rows and logs an `out` activity row for each,
  /// so this revalidates inventory on top of ownership.
  Future<({int count, String? error})> bulkRemoveFromCollection({
    required String userId,
    required List<int> cardIds,
  }) async {
    final result = await _ref
        .read(expansionsRepositoryProvider)
        .bulkRemoveUserCards(userId: userId, cardIds: cardIds);
    _revalidateBulkOwnership(cardIds);
    _revalidateInventory();
    return result;
  }

  void _revalidateBulkOwnership(List<int> cardIds) {
    for (final cardId in cardIds) {
      _ref.invalidate(ownedQuantityProvider(cardId));
    }
    _ref.invalidate(collectionProvider);
    // Family-wide: the controller doesn't know which pack slug the caller
    // acted on, and a card can appear in only one expansion anyway.
    _ref.invalidate(packOwnedQuantitiesProvider);
  }

  Future<String?> setWishlisted(int cardId, bool wishlisted) async {
    final error = await _ref
        .read(portfolioRepositoryProvider)
        .setWishlisted(cardId, wishlisted);
    if (error == null) _revalidateWishlist(cardId);
    return error;
  }

  /// Confirms an inventory draft (`user_inventory.is_draft` → false) and
  /// syncs the quantity into `user_cards` — the RPC only does the former,
  /// mirroring the web's `handleSaveDraft` making both calls itself.
  Future<String?> confirmInventoryDraft({
    required String userId,
    required int recordId,
    required int cardId,
    required int quantity,
    required int unitPrice,
  }) async {
    final repo = _ref.read(portfolioRepositoryProvider);
    final confirmError = await repo.confirmDraftRecord(
      userId: userId,
      recordId: recordId,
      quantity: quantity,
      unitPrice: unitPrice,
    );
    if (confirmError != null) return confirmError;
    final qtyError = await _ref
        .read(expansionsRepositoryProvider)
        .upsertUserCard(userId: userId, cardId: cardId, delta: quantity);
    _revalidateOwnership(cardId);
    _revalidateInventory();
    return qtyError;
  }

  /// Bulk-removes inventory records. `bulk_remove_inventory` already
  /// decrements `user_cards` and logs the activity row server-side, so
  /// this only needs to revalidate — no follow-up quantity call.
  Future<String?> removeInventory({
    required String userId,
    required List<({int recordId, int delQty, int cardId})> items,
  }) async {
    final repo = _ref.read(portfolioRepositoryProvider);
    final error = await repo.bulkRemoveInventory(
      userId,
      items.map((i) => (recordId: i.recordId, delQty: i.delQty)).toList(),
    );
    if (error == null) {
      _revalidateInventory();
      _ref.invalidate(collectionProvider);
      for (final item in items) {
        _ref.invalidate(ownedQuantityProvider(item.cardId));
      }
    }
    return error;
  }

  void _revalidateOwnership(int cardId) {
    _ref.invalidate(ownedQuantityProvider(cardId));
    _ref.invalidate(collectionProvider);
  }

  void _revalidateWishlist(int cardId) {
    // `isWishlistedProvider` derives from `wishlistedIdsProvider` via
    // `ref.watch`, so invalidating the latter refreshes both automatically.
    _ref.invalidate(wishlistedIdsProvider);
    _ref.invalidate(wishlistProvider);
  }

  void _revalidateInventory() {
    _ref.invalidate(inventoryRecordsProvider);
    _ref.invalidate(inventoryDraftsProvider);
    _ref.invalidate(inventoryActivityProvider);
  }

  Future<({DeckModel? deck, String? error})> createDeck({
    required String userId,
    required String name,
    String description = '',
  }) async {
    final result = await _ref
        .read(portfolioRepositoryProvider)
        .createDeck(userId: userId, name: name, description: description);
    if (result.error == null) _ref.invalidate(decksProvider);
    return result;
  }

  Future<String?> updateDeck({
    required String deckId,
    required String userId,
    required String name,
    required String description,
  }) async {
    final error = await _ref
        .read(portfolioRepositoryProvider)
        .updateDeck(
          deckId: deckId,
          userId: userId,
          name: name,
          description: description,
        );
    if (error == null) _ref.invalidate(decksProvider);
    return error;
  }

  Future<String?> deleteDeck({
    required String deckId,
    required String userId,
  }) async {
    final error = await _ref
        .read(portfolioRepositoryProvider)
        .deleteDeck(deckId: deckId, userId: userId);
    if (error == null) _ref.invalidate(decksProvider);
    return error;
  }

  Future<({DeckModel? deck, String? error})> duplicateDeck(
    String sourceDeckId,
  ) async {
    final result = await _ref
        .read(portfolioRepositoryProvider)
        .duplicateDeck(sourceDeckId);
    if (result.error == null) _ref.invalidate(decksProvider);
    return result;
  }

  /// Adds/removes/adjusts a card in a deck. Refreshes both the deck's own
  /// card list and the deck list's card-count badge.
  Future<String?> upsertDeckCard({
    required String deckId,
    required int cardId,
    required int delta,
  }) async {
    final error = await _ref
        .read(portfolioRepositoryProvider)
        .upsertDeckCard(deckId: deckId, cardId: cardId, delta: delta);
    if (error == null) {
      _ref.invalidate(deckCardsProvider(deckId));
      _ref.invalidate(decksProvider);
    }
    return error;
  }
}

final cardOwnershipControllerProvider = Provider(
  (ref) => CardOwnershipController(ref),
);
