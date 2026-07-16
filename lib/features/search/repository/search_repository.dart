import '../../../shared/data/dummy_catalog.dart';
import '../../../shared/models/card_model.dart';

class SearchFilterOptions {
  const SearchFilterOptions({required this.rarities, required this.packMarks});

  final List<String> rarities;
  final List<String> packMarks;
}

/// Data access for the Advanced Search feature. Stands in for
/// `fetchSearchFilterOptionsServer` / `fetchAdvancedSearchPageAction` on the
/// web while this pass only ports the UI with dummy data.
class SearchRepository {
  Future<SearchFilterOptions> fetchFilterOptions() async {
    await Future.delayed(const Duration(milliseconds: 150));
    final rarities =
        DummyCatalog.allCards.map((c) => c.rarity).whereType<String>().toSet().toList()
          ..sort();
    final marks = DummyCatalog.packs.map((p) => p.mark).toSet().toList()
      ..sort();
    return SearchFilterOptions(rarities: rarities, packMarks: marks);
  }

  Future<List<CardModel>> search({
    required String query,
    required Set<String> rarities,
    required Set<String> packMarks,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final q = query.trim().toLowerCase();
    return DummyCatalog.allCards.where((c) {
      final matchesQuery = q.isEmpty || c.name.toLowerCase().contains(q);
      final matchesRarity = rarities.isEmpty || rarities.contains(c.rarity);
      final matchesPack =
          packMarks.isEmpty || packMarks.contains(c.expansionCode);
      return matchesQuery && matchesRarity && matchesPack;
    }).toList();
  }
}
