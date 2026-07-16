import '../../../shared/data/dummy_catalog.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/pack_model.dart';

/// Data access for the Expansions feature. Stands in for
/// `fetchPacksGroupedBySeries` / `fetchPacks` on the web while this pass
/// only ports the UI with dummy data.
class ExpansionsRepository {
  Future<List<SeriesGroup>> fetchSeriesGroups() async {
    await Future.delayed(const Duration(milliseconds: 250));
    return DummyCatalog.seriesGroups;
  }

  Future<PackModel?> fetchPack(String slug) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return DummyCatalog.packBySlug(slug);
  }

  Future<List<CardModel>> fetchCardsForPack(String slug) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return DummyCatalog.cardsByPack[slug] ?? const [];
  }

  Future<CardModel?> fetchCard(int id) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return DummyCatalog.cardById(id);
  }

  Future<List<ListingModel>> fetchListingsForCard(int cardId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return DummyCatalog.listings.where((l) => l.card.id == cardId).toList();
  }
}
