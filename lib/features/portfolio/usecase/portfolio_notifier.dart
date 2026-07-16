import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/card_model.dart';
import '../../../shared/models/deck_model.dart';
import '../repository/models/deck_card_entry.dart';
import '../repository/models/wantlist_model.dart';
import '../repository/portfolio_repository.dart';

final portfolioRepositoryProvider = Provider((ref) => PortfolioRepository());

final collectionProvider = FutureProvider<List<CardModel>>((ref) {
  return ref.read(portfolioRepositoryProvider).fetchCollection();
});

final decksProvider = FutureProvider<List<DeckModel>>((ref) {
  return ref.read(portfolioRepositoryProvider).fetchDecks();
});

final deckCardsProvider = FutureProvider.family<List<DeckCardEntry>, int>((
  ref,
  deckId,
) {
  return ref.read(portfolioRepositoryProvider).fetchDeckCards(deckId);
});

final listsProvider = FutureProvider<List<WantlistModel>>((ref) {
  return ref.read(portfolioRepositoryProvider).fetchLists();
});

final listCardsProvider = FutureProvider.family<List<CardModel>, int>((
  ref,
  listId,
) {
  return ref.read(portfolioRepositoryProvider).fetchListCards(listId);
});
