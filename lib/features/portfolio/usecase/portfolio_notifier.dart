import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/deck_model.dart';
import '../repository/models/deck_card_entry.dart';
import '../repository/models/inventory_entry.dart';
import '../repository/models/wantlist_model.dart';
import '../repository/portfolio_repository.dart';

/// The collection's search query. Lifted out of the filter bar because the
/// box now sits at the top of the page, above the scrolling grid that owns
/// the rest of the filters.
final collectionSearchProvider = StateProvider<String>((ref) => '');

/// Whether Koleksi is showing the wishlist instead of the collection. The
/// heart beside the search box flips it — a switch rather than a trip to
/// another page, since the search box and filters serve both.
final showWishlistProvider = StateProvider<bool>((ref) => false);

final portfolioRepositoryProvider = Provider((ref) {
  return PortfolioRepository(ref.read(supabaseClientProvider));
});

/// Empty for guests — mirrors the collection/deck/wishlist queries only
/// running once a `user` is present.
final collectionProvider = FutureProvider<List<CardModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(portfolioRepositoryProvider).fetchCollection(user.id);
});

final decksProvider = FutureProvider<List<DeckModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(portfolioRepositoryProvider).fetchDecks(user.id);
});

final deckCardsProvider = FutureProvider.family<List<DeckCardEntry>, String>((
  ref,
  deckId,
) {
  return ref.read(portfolioRepositoryProvider).fetchDeckCards(deckId);
});

final wishlistProvider = FutureProvider<List<CardModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(portfolioRepositoryProvider).fetchWishlist(user.id);
});

/// Single source of truth for "which cards are wishlisted" — fetched once
/// via `get_my_wishlist` (the only thing that can actually see
/// `card_wishlists`, since it's RLS-locked with no policies and only
/// readable through that `SECURITY DEFINER` RPC). `isWishlistedProvider`
/// derives from this instead of querying per-card, so a card detail
/// page's heart icon and the Wishlist tab always agree and invalidate
/// together.
final wishlistedIdsProvider = FutureProvider<Set<int>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const {});
  return ref.read(portfolioRepositoryProvider).fetchWishlistedCardIds();
});

final isWishlistedProvider = Provider.family<bool, int>((ref, cardId) {
  final ids = ref.watch(wishlistedIdsProvider).valueOrNull;
  return ids?.contains(cardId) ?? false;
});

final listsProvider = FutureProvider<List<WantlistModel>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(portfolioRepositoryProvider).fetchLists(user.id);
});

final listCardsProvider = FutureProvider.family<List<CardModel>, String>((
  ref,
  listId,
) {
  return ref.read(portfolioRepositoryProvider).fetchListCards(listId);
});

final inventoryRecordsProvider = FutureProvider<List<InventoryEntry>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(portfolioRepositoryProvider).fetchInventoryRecords(user.id);
});

/// Staged-but-not-yet-confirmed rows from the "Tambahkan" flow.
final inventoryDraftsProvider = FutureProvider<List<InventoryEntry>>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(portfolioRepositoryProvider).fetchDraftRecords(user.id);
});

final inventoryActivityProvider = FutureProvider<List<InventoryActivityEntry>>((
  ref,
) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const []);
  return ref.read(portfolioRepositoryProvider).fetchInventoryActivity(user.id);
});

/// Catalog search for the "Tambahkan" tab's card picker.
final cardSearchPickerProvider = FutureProvider.family<List<CardModel>, String>(
  (ref, query) {
    return ref.read(portfolioRepositoryProvider).searchCardsPicker(query);
  },
);
