import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/card_model.dart';
import '../../portfolio/usecase/portfolio_notifier.dart';
import '../repository/models/portfolio_value.dart';
import '../repository/portfolio_value_repository.dart';

/// Which portfolio the Beranda header is valuing. Defaults to the whole
/// collection.
final selectedPortfolioProvider = StateProvider<PortfolioTarget>(
  (ref) => PortfolioTarget.primary,
);

/// The chart's selected timeline. `1B` by default, as sketched.
final portfolioRangeProvider = StateProvider<PortfolioRange>(
  (ref) => PortfolioRange.fallback,
);

/// Everything the user can point the header at: the full collection first,
/// then each saved list.
final portfolioTargetsProvider = Provider<List<PortfolioTarget>>((ref) {
  final lists = ref.watch(listsProvider).valueOrNull ?? const [];
  return [
    PortfolioTarget.primary,
    for (final list in lists)
      PortfolioTarget(name: list.name, listId: list.id),
  ];
});

/// The selected portfolio's cards, priced.
///
/// Only cards the user actually holds count toward the value: a list can
/// name cards that aren't in the collection, and those contribute nothing
/// rather than being valued as if owned.
final portfolioHoldingsProvider = FutureProvider<List<PortfolioHolding>>((
  ref,
) async {
  final target = ref.watch(selectedPortfolioProvider);
  final collection = await ref.watch(collectionProvider.future);

  var cards = collection;
  if (!target.isPrimary) {
    final listCards = await ref.watch(
      listCardsProvider(target.listId!).future,
    );
    final wanted = {for (final card in listCards) card.id};
    cards = collection.where((card) => wanted.contains(card.id)).toList();
  }

  return [
    for (final card in cards)
      if (card.owned > 0)
        PortfolioHolding(
          cardId: card.id,
          name: card.name,
          collectorNumber: card.collectorNumber,
          expansionCode: card.expansionCode,
          rarity: card.rarity,
          packSlug: card.packSlug,
          quantity: card.owned,
          unitPrice: card.marketPrice ?? 0,
          imageUrl: card.imageUrl,
        ),
  ];
});

/// Today's headline number under "Portofolio Utama" — the same arithmetic
/// the Koleksi page totals with, so the two screens can't disagree.
final portfolioValueProvider = Provider<int>((ref) {
  final holdings = ref.watch(portfolioHoldingsProvider).valueOrNull;
  if (holdings == null) return 0;
  return holdings.fold(0, (sum, holding) => sum + holding.value);
});

/// "Nilai Tertinggi" — the holdings worth the most, biggest first.
final topHoldingsProvider = Provider<List<PortfolioHolding>>((ref) {
  final holdings = [...?ref.watch(portfolioHoldingsProvider).valueOrNull];
  holdings.sort((a, b) => b.value.compareTo(a.value));
  return holdings;
});

/// The chart series for the selected portfolio and range.
final portfolioValueSeriesProvider =
    FutureProvider<List<PortfolioValuePoint>>((ref) async {
  final holdings = await ref.watch(portfolioHoldingsProvider.future);
  final range = ref.watch(portfolioRangeProvider);
  return ref
      .read(portfolioValueRepositoryProvider)
      .fetchValueSeries(holdings: holdings, range: range);
});

/// Change across the visible series — the figure under the headline value.
class PortfolioDelta {
  const PortfolioDelta({required this.amount, required this.percent});

  final int amount;
  final double percent;

  bool get isUp => amount >= 0;
}

final portfolioDeltaProvider = Provider<PortfolioDelta?>((ref) {
  final series = ref.watch(portfolioValueSeriesProvider).valueOrNull;
  if (series == null || series.length < 2) return null;
  final first = series.first.value;
  final last = series.last.value;
  final amount = last - first;
  final percent = first == 0 ? (amount == 0 ? 0.0 : 100.0) : amount / first * 100;
  return PortfolioDelta(amount: amount, percent: percent);
});

/// Convenience for the "N kartu" caption next to the value.
final portfolioCardCountProvider = Provider<({int unique, int total})>((ref) {
  final holdings = ref.watch(portfolioHoldingsProvider).valueOrNull ?? const [];
  return (
    unique: holdings.length,
    total: holdings.fold(0, (sum, h) => sum + h.quantity),
  );
});

/// Re-exported so the Beranda widgets don't reach into the portfolio feature
/// for the card model they render.
typedef PortfolioCard = CardModel;
