import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/catalog_language_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/pack_model.dart';
import '../../../shared/utils/primary_collection.dart';
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

/// Sets in "Jelajahi Rilis Terbaru".
const _latestReleaseCount = 8;

/// "Jelajahi Rilis Terbaru": the newest sets in the catalog being browsed,
/// from the same list the expansions page reads (newest release first).
final latestReleasesProvider = FutureProvider<List<PackModel>>((ref) async {
  final packs = await ref.watch(explorePacksProvider.future);
  return packs.take(_latestReleaseCount).toList();
});

/// How many cards of each latest release the main collection holds, keyed
/// by slug. Empty when signed out: the cards then show no progress at all,
/// rather than a 0/N that reads as the reader's own.
final latestReleaseOwnedProvider = FutureProvider<Map<String, int>?>((
  ref,
) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return null;
  final packs = await ref.watch(latestReleasesProvider.future);
  if (packs.isEmpty) return const {};
  final collectionId = await primaryCollectionId(
    ref.read(supabaseClientProvider),
    user.id,
  );
  if (collectionId == null) return const {};
  return ref
      .read(homeRepositoryProvider)
      .fetchOwnedCountsByExpansion(
        collectionId: collectionId,
        slugs: [for (final pack in packs) pack.slug],
        language: ref.watch(catalogLanguageProvider).raw,
      );
});
