import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../shared/models/card_model.dart';
import '../../expansions/usecase/expansions_notifier.dart';
import '../../home/usecase/portfolio_value_notifier.dart';

/// What a card grid's counters need: how many of each card sits in the
/// portfolio the "Portofolio: …" switcher names, and a way to change it.
///
/// Shared so the expansion page and both search pages count against the
/// same shelf. Each used to decide that for itself, and the search pages
/// didn't ask at all — catalog rows know nothing about the viewer, so every
/// result read as unowned.

/// [cards] with `owned` filled in from the selected portfolio.
///
/// [collectionId] is the one the caller already resolved, if it did; left
/// null it is read here. Best effort: a failure returns the cards as they
/// came, at zero, rather than failing the page they are on.
Future<List<CardModel>> withOwnedQuantities(
  Ref ref,
  List<CardModel> cards, {
  String? collectionId,
}) async {
  final user = ref.read(authProvider).valueOrNull;
  if (user == null || cards.isEmpty) return cards;
  try {
    final target =
        collectionId ?? await ref.read(selectedCollectionIdProvider.future);
    final owned = await ref
        .read(expansionsRepositoryProvider)
        .fetchOwnedQuantities(user.id, [
          for (final c in cards) c.id,
        ], collectionId: target);
    return [for (final c in cards) c.copyWith(owned: owned[c.id] ?? 0)];
  } catch (_) {
    return cards;
  }
}

/// Files [next] copies of [card] into the selected portfolio, returning a
/// message on failure.
///
/// The two shelves take different calls: the main collection moves by a
/// delta from [card]'s current count, a list is told the number it should
/// hold.
Future<String?> setPortfolioQuantity(
  WidgetRef ref,
  CardModel card,
  int next,
) async {
  final user = ref.read(authProvider).valueOrNull;
  if (user == null) return 'Masuk dulu untuk menambah ke koleksi.';

  final listId = ref.read(selectedPortfolioProvider).listId;
  final controller = ref.read(cardOwnershipControllerProvider);
  return listId == null
      ? controller.adjustQuantity(
          userId: user.id,
          cardId: card.id,
          delta: next - card.owned,
        )
      : controller.setListCardQuantity(
          listId: listId,
          cardId: card.id,
          quantity: next,
        );
}
