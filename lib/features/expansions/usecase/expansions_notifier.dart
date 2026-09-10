import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/catalog_language_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_condition.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/listing_model.dart';
import '../../../shared/models/pack_model.dart';
import '../repository/expansions_repository.dart';
import '../repository/models/market_models.dart';

final expansionsRepositoryProvider = Provider((ref) {
  return ExpansionsRepository(ref.read(supabaseClientProvider));
});

/// Re-fetched when the catalog language changes — each language has its
/// own expansion rows, so the whole grouping swaps over.
final seriesGroupsProvider = FutureProvider<List<SeriesGroup>>((ref) {
  final language = ref.watch(catalogLanguageProvider);
  return ref
      .read(expansionsRepositoryProvider)
      .fetchSeriesGroups(language: language.raw);
});

/// The expansion a *card* belongs to, looked up in that card's language.
///
/// [packDetailProvider] keys off the catalog language switch, which is right
/// for browsing an expansion but wrong for naming the one a card came from:
/// each language has its own `expansions` row, so an English card viewed
/// while the catalog is set to Indonesian finds nothing.
final packForCardProvider =
    FutureProvider.family<PackModel?, ({String slug, String language})>((
      ref,
      key,
    ) {
      return ref
          .read(expansionsRepositoryProvider)
          .fetchPack(key.slug, language: key.language);
    });

final packDetailProvider = FutureProvider.family<PackModel?, String>((
  ref,
  slug,
) {
  final language = ref.watch(catalogLanguageProvider);
  return ref
      .read(expansionsRepositoryProvider)
      .fetchPack(slug, language: language.raw);
});

final packCardsProvider = FutureProvider.family<List<CardModel>, String>((
  ref,
  slug,
) {
  final language = ref.watch(catalogLanguageProvider);
  return ref
      .read(expansionsRepositoryProvider)
      .fetchCardsForPack(slug, language: language.raw);
});

/// Ports the `relatedCards` half of the card detail page's server fetch:
/// other prints of the card on screen. The web excludes the current id in
/// the query *and* again client-side; one is enough.
final relatedCardsProvider =
    FutureProvider.family<List<CardModel>, ({String name, int excludeId})>((
      ref,
      key,
    ) {
      final language = ref.watch(catalogLanguageProvider);
      return ref
          .read(expansionsRepositoryProvider)
          .fetchCardsByName(
            key.name,
            excludeId: key.excludeId,
            language: language.raw,
          );
    });

/// Ports `usePackCardPrices(expansionCode)` — the cached market price of
/// every card in one expansion.
///
/// Kept apart from [packCardsProvider] so the grid paints as soon as the
/// catalog rows arrive and the prices fill in behind them, which is how the
/// web page behaves. The pack slug is the expansion code lowercased, which
/// is what the RPC matches on.
final packCardPricesProvider =
    FutureProvider.family<Map<int, CardMarketPrice>, String>((ref, slug) {
      return ref.read(expansionsRepositoryProvider).fetchPackCardPrices(slug);
    });

/// Ports `useUserCardQuantities(cardIds)` as the pack detail page uses it:
/// the owned quantity of every card in one expansion, keyed by card id.
/// Empty for guests, mirroring the hook only fetching once a `user` exists.
final packOwnedQuantitiesProvider =
    FutureProvider.family<Map<int, int>, String>((ref, slug) async {
      final user = ref.watch(authProvider).valueOrNull;
      if (user == null) return const {};
      final cards = await ref.watch(packCardsProvider(slug).future);
      return ref
          .read(expansionsRepositoryProvider)
          .fetchOwnedQuantities(user.id, cards.map((c) => c.id).toList());
    });

final cardDetailProvider = FutureProvider.family<CardModel?, int>((ref, id) {
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
final ownedQuantityProvider = FutureProvider.family<int, int>((
  ref,
  cardId,
) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return 0;
  return ref
      .read(expansionsRepositoryProvider)
      .fetchOwnedQuantity(user.id, cardId);
});

/// The daily price series behind the market activity chart. [days] is null
/// for the "1 Thn" range, matching `get_market_price_series`' own default.
final marketPriceSeriesProvider =
    FutureProvider.family<List<MarketPricePoint>, ({int cardId, int? days})>((
      ref,
      key,
    ) {
      return ref
          .read(expansionsRepositoryProvider)
          .fetchMarketPriceSeries(key.cardId, days: key.days);
    });

/// Ports `useMarketHeadline` — the last traded price plus its 7-day move,
/// derived from the same series the activity chart draws.
final marketHeadlineProvider = FutureProvider.family<MarketHeadline?, int>((
  ref,
  cardId,
) async {
  final series = await ref.watch(
    marketPriceSeriesProvider((cardId: cardId, days: headlineDays)).future,
  );
  return MarketHeadline.fromSeries(series);
});

/// Cached headline price — the fallback the market header shows when a card
/// has no sale history to derive a series from.
final cardMarketPriceProvider = FutureProvider.family<CardMarketPrice?, int>((
  ref,
  cardId,
) {
  return ref.read(expansionsRepositoryProvider).fetchCardMarketPrice(cardId);
});

/// The bid/ask ladder, re-fetched whenever the condition filter changes.
final orderBookProvider =
    FutureProvider.family<
      OrderBookData,
      ({int cardId, CardCondition? condition})
    >((ref, key) {
      // Own-bid highlighting is resolved server-side from the caller's id, so
      // the book has to be refetched when the viewer signs in or out.
      ref.watch(authProvider);
      return ref
          .read(expansionsRepositoryProvider)
          .fetchOrderBook(key.cardId, condition: key.condition);
    });

/// One page of settled transactions for the "Histori Transaksi" table.
final cardSalesProvider =
    FutureProvider.family<CardSalesPage, ({int cardId, int limit})>((ref, key) {
      return ref
          .read(expansionsRepositoryProvider)
          .fetchCardSales(key.cardId, limit: key.limit);
    });

/// Keyed by (name, evolvesFrom, language) rather than card id — the pool
/// only depends on where a card sits in its line, not the exact print row,
/// but it is language-specific.
///
/// The language comes from the card being viewed rather than
/// [catalogLanguageProvider]: a card page reached from the market or a
/// direct link can be in a different language than the catalog switch.
final evolutionPoolProvider =
    FutureProvider.family<
      List<CardModel>,
      ({String name, String? evolvesFrom})
    >((ref, seed) {
      final seeds = [
        seed.name,
        if (seed.evolvesFrom != null) seed.evolvesFrom!,
      ];
      return ref.read(expansionsRepositoryProvider).fetchEvolutionPool(seeds);
    });
