import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/pack_model.dart';
import '../repository/home_repository.dart';

final homeRepositoryProvider = Provider((ref) => HomeRepository());

final recentlyViewedPacksProvider = FutureProvider<List<PackModel>>((ref) {
  return ref.read(homeRepositoryProvider).fetchRecentlyViewed();
});

final explorePacksProvider = FutureProvider<List<PackModel>>((ref) {
  return ref.read(homeRepositoryProvider).fetchExplorePacks();
});
