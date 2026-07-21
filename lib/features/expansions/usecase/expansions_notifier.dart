import 'package:flutter_riverpod/flutter_riverpod.dart';

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
