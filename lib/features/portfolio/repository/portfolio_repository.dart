import '../../../shared/data/dummy_catalog.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/deck_model.dart';
import 'models/deck_card_entry.dart';
import 'models/wantlist_model.dart';

/// Data access for the Portfolio feature (Koleksi / Deck / Inventori tabs).
/// Stands in for the web's Supabase-backed portfolio queries while this
/// pass only ports the UI with dummy data.
class PortfolioRepository {
  Future<List<CardModel>> fetchCollection() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return DummyCatalog.allCards.where((c) => c.owned > 0).toList();
  }

  Future<List<DeckModel>> fetchDecks() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return const [
      DeckModel(
        id: 1,
        name: 'Charizard ex Aggro',
        cardCount: 60,
        format: 'Standard',
        updatedAt: '2 hari lalu',
      ),
      DeckModel(
        id: 2,
        name: 'Lost Box Control',
        cardCount: 58,
        format: 'Standard',
        updatedAt: '1 minggu lalu',
      ),
      DeckModel(
        id: 3,
        name: 'Umbreon VMAX',
        cardCount: 60,
        format: 'Expanded',
        updatedAt: '3 minggu lalu',
      ),
    ];
  }

  Future<List<DeckCardEntry>> fetchDeckCards(int deckId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final cards = DummyCatalog.allCards.skip(deckId * 3).take(18).toList();
    final categories = DeckCategory.values;
    return List.generate(cards.length, (i) {
      return DeckCardEntry(
        card: cards[i],
        quantity: 1 + (i % 4 == 0 ? 1 : 0),
        category: categories[i % categories.length],
      );
    });
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
