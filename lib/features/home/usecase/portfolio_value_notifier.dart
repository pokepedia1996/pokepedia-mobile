import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/card_model.dart';
import '../../portfolio/usecase/portfolio_notifier.dart';
import '../repository/models/portfolio_value.dart';
import '../repository/portfolio_value_repository.dart';

/// Which portfolio Beranda opens on, as the user set it with the star in the
/// picker. Held as a list id (null = the whole collection).
///
/// Local rather than server-side: `lists` has no default flag, and this is a
/// per-person view preference rather than data about the list.
class DefaultPortfolioNotifier extends Notifier<String?> {
  static const _key = 'default_portfolio_list_id';

  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_key);
    if (id != null && id.isNotEmpty) state = id;
  }

  Future<void> set(String? listId) async {
    state = listId;
    final prefs = await SharedPreferences.getInstance();
    if (listId == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, listId);
    }
  }
}

final defaultPortfolioIdProvider =
    NotifierProvider<DefaultPortfolioNotifier, String?>(
      DefaultPortfolioNotifier.new,
    );

/// Which portfolio the Beranda header is valuing: what the user picked this
/// session, otherwise their starred default, otherwise the whole collection.
class SelectedPortfolioNotifier extends Notifier<PortfolioTarget> {
  /// This session's explicit pick, which outranks the stored default until
  /// the target stops existing (a deleted list).
  PortfolioTarget? _picked;

  @override
  PortfolioTarget build() {
    final targets = ref.watch(portfolioTargetsProvider);
    final picked = _picked;
    if (picked != null && targets.contains(picked)) return picked;

    final defaultId = ref.watch(defaultPortfolioIdProvider);
    return targets.firstWhere(
      (target) => target.listId == defaultId,
      orElse: () => PortfolioTarget.primary,
    );
  }

  void select(PortfolioTarget target) {
    _picked = target;
    state = target;
  }
}

final selectedPortfolioProvider =
    NotifierProvider<SelectedPortfolioNotifier, PortfolioTarget>(
      SelectedPortfolioNotifier.new,
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
    for (final list in lists) PortfolioTarget(name: list.name, listId: list.id),
  ];
});

/// The selected portfolio's cards — the whole collection, or the ones the
/// chosen list holds. What the Koleksi page lists.
///
/// Each list keeps its own cards at its own quantities rather than pointing
/// into `user_cards`, so this reads the list itself. Intersecting the two
/// would hide every card that was filed into a list instead of the main
/// collection, which is most of them.
final selectedPortfolioCardsProvider = FutureProvider<List<CardModel>>((ref) {
  final target = ref.watch(selectedPortfolioProvider);
  if (target.isPrimary) return ref.watch(collectionProvider.future);
  return ref.watch(listCardsProvider(target.listId!).future);
});

/// The selected portfolio's cards, priced.
///
/// Derived from the same provider the grid renders, so the headline value
/// and the cards on screen can't disagree about what's in the portfolio.
final portfolioHoldingsProvider = FutureProvider<List<PortfolioHolding>>((
  ref,
) async {
  final cards = await ref.watch(selectedPortfolioCardsProvider.future);

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
///
/// Yesterday and earlier come from `portfolio_value_snapshots`; **today is
/// always computed live** from the priced holdings.
///
/// Today is deliberately not read from the table. The snapshot is taken once
/// at 00:20 UTC, so a card added at noon would not move the chart until the
/// following night — the reader would add something worth real money and
/// watch the line ignore it. The live value is the same arithmetic
/// [portfolioValueProvider] already shows as the headline, so the chart's
/// last point and the number above it can never disagree either.
///
/// `portfolio_value_snapshots` records the whole collection, which is what
/// "Portofolio Utama" is. A single list has no snapshot of its own, so the
/// chart says so there rather than drawing the collection's line under a
/// list's name — a wrong number rather than a missing one.
final portfolioValueSeriesProvider = FutureProvider<List<PortfolioValuePoint>>((
  ref,
) async {
  final target = ref.watch(selectedPortfolioProvider);
  if (!target.isPrimary) return const [];

  final range = ref.watch(portfolioRangeProvider);
  final history = await ref
      .read(portfolioValueRepositoryProvider)
      .fetchValueSeries(range: range);

  final holdings = await ref.watch(portfolioHoldingsProvider.future);
  if (holdings.isEmpty) return history;

  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  final live = holdings.fold(0, (sum, holding) => sum + holding.value);

  // Today's snapshot, if the cron already wrote one, is replaced rather than
  // appended to: two points for one day would draw a vertical step.
  return [
    ...history.where((point) => point.day.isBefore(today)),
    PortfolioValuePoint(day: today, value: live),
  ];
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
  final percent = first == 0
      ? (amount == 0 ? 0.0 : 100.0)
      : amount / first * 100;
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
