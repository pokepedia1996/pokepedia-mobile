import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/pack_model.dart';
import '../repository/expansions_repository.dart';

final expansionsRepositoryProvider = Provider((ref) {
  return ExpansionsRepository(ref.read(supabaseClientProvider));
});

final seriesGroupsProvider = FutureProvider<List<SeriesGroup>>((ref) {
  return ref.read(expansionsRepositoryProvider).fetchSeriesGroups();
});

final packDetailProvider = FutureProvider.family<PackModel?, String>((
  ref,
  slug,
) {
  return ref.read(expansionsRepositoryProvider).fetchPack(slug);
});

final packCardsProvider = FutureProvider.family<List<CardModel>, String>((
  ref,
  slug,
) {
  return ref.read(expansionsRepositoryProvider).fetchCardsForPack(slug);
});

final cardDetailProvider = FutureProvider.family<CardModel?, int>((
  ref,
  id,
) {
  return ref.read(expansionsRepositoryProvider).fetchCard(id);
});

final cardListingsProvider = FutureProvider.family<List<ListingModel>, int>((
  ref,
  cardId,
) {
  return ref.read(expansionsRepositoryProvider).fetchListingsForCard(cardId);
});

/// 0 for guests — mirrors `useUserCardQuantities` only fetching once a
/// `user` is present.
final ownedQuantityProvider = FutureProvider.family<int, int>((ref, cardId) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return 0;
  return ref.read(expansionsRepositoryProvider).fetchOwnedQuantity(user.id, cardId);
});

/// Keyed by (name, evolvesFrom) rather than card id — the evolution pool
/// only depends on where a card sits in its line, not the exact print row.
final evolutionPoolProvider = FutureProvider.family<List<CardModel>, (String name, String? evolvesFrom)>((
  ref,
  seed,
) {
  final seeds = [seed.$1, if (seed.$2 != null) seed.$2!];
  return ref.read(expansionsRepositoryProvider).fetchEvolutionPool(seeds);
});
