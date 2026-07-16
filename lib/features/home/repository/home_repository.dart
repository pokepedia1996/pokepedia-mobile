import '../../../shared/data/dummy_catalog.dart';
import '../../../shared/models/pack_model.dart';

/// Data access for the Home feature. Stands in for the web's
/// `fetchPacksGroupedBySeries` / recently-viewed cache while this pass only
/// ports the UI with dummy data.
class HomeRepository {
  Future<List<PackModel>> fetchRecentlyViewed() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return DummyCatalog.packs.take(6).toList();
  }

  Future<List<PackModel>> fetchExplorePacks() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return DummyCatalog.packs;
  }
}
