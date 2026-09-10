import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/catalog_language_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/pack_model.dart';
import '../../expansions/usecase/expansions_notifier.dart';
import '../../expansions/usecase/recently_viewed_provider.dart';
import '../repository/home_repository.dart';

final homeRepositoryProvider = Provider((ref) {
  return HomeRepository(
    ref.read(supabaseClientProvider),
    ref.read(expansionsRepositoryProvider),
  );
});

final recentlyViewedPacksProvider = FutureProvider<List<PackModel>>((ref) {
  final slugs = ref.watch(recentlyViewedSlugsProvider);
  final language = ref.watch(catalogLanguageProvider);
  return ref
      .read(homeRepositoryProvider)
      .fetchRecentlyViewed(slugs, language: language.raw);
});

final explorePacksProvider = FutureProvider<List<PackModel>>((ref) {
  final language = ref.watch(catalogLanguageProvider);
  return ref
      .read(homeRepositoryProvider)
      .fetchExplorePacks(language: language.raw);
});
