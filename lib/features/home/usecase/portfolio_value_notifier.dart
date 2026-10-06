import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/utils/primary_collection.dart';
import '../../portfolio/usecase/collection_page_notifier.dart';
import '../../portfolio/usecase/portfolio_notifier.dart';
import '../repository/models/portfolio_value.dart';
import '../repository/portfolio_value_repository.dart';

/// Re-exported so the Beranda widgets read the summary without reaching into
/// the portfolio feature.
export '../../portfolio/usecase/collection_page_notifier.dart'
    show collectionSummaryProvider;

/// Which portfolio the Beranda header is valuing: what the user picked this
/// session, otherwise the whole collection.
///
/// There is no stored default any more — the star that set one read as a
/// second, invisible kind of selection, and a portfolio quietly deciding
/// what Beranda opens on is worse than picking it each time.
class SelectedPortfolioNotifier extends Notifier<PortfolioTarget> {
  /// This session's explicit pick, which outranks the stored default until
  /// the target stops existing (a deleted list).
  PortfolioTarget? _picked;

  @override
  PortfolioTarget build() {
    final targets = ref.watch(portfolioTargetsProvider);
    final picked = _picked;
    if (picked != null && targets.contains(picked)) return picked;
    return PortfolioTarget.primary;
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
/// into the primary collection, so this reads the list itself. Intersecting the two
/// would hide every card that was filed into a list instead of the main
/// collection, which is most of them.
final selectedPortfolioCardsProvider = FutureProvider<List<CardModel>>((ref) {
  final target = ref.watch(selectedPortfolioProvider);
  if (target.isPrimary) return ref.watch(collectionProvider.future);
  return ref.watch(listCardsProvider(target.listId!).future);
});

/// The selected portfolio's cards, priced — every one of them, which is a
/// full read of the collection. Only "Nilai Tertinggi" needs that; the
/// headline figures come from [collectionSummaryProvider].
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
          priceChangePct: card.priceChangePct,
        ),
  ];
});

/// Today's headline number under "Portofolio Utama" — the same summary the
/// Koleksi header reads, so the two screens can't disagree.
final portfolioValueProvider = Provider<int>((ref) {
  return ref.watch(collectionSummaryProvider).valueOrNull?.totalValue ?? 0;
});

/// "Nilai Tertinggi" — the holdings worth the most, biggest first.
final topHoldingsProvider = Provider<List<PortfolioHolding>>((ref) {
  final holdings = [...?ref.watch(portfolioHoldingsProvider).valueOrNull];
  holdings.sort((a, b) => b.value.compareTo(a.value));
  return holdings;
});

/// The collection id behind the selected target.
///
/// A non-primary target already carries one; "Utama" doesn't, because it is
/// whichever collection `is_primary` happens to be, so that one is resolved.
/// Null only when signed out or when the account somehow has no primary row.
final selectedCollectionIdProvider = FutureProvider<String?>((ref) async {
  final target = ref.watch(selectedPortfolioProvider);
  if (!target.isPrimary) return target.listId;
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return null;
  return primaryCollectionId(ref.read(supabaseClientProvider), user.id);
});

/// The chart series for the selected portfolio and range.
///
/// Yesterday and earlier come from `collection_value_snapshots`; **today is
/// always computed live** from the collection summary.
///
/// Today is deliberately not read from the table. The snapshot is taken once
/// at 00:20 UTC, so a card added at noon would not move the chart until the
/// following night — the reader would add something worth real money and
/// watch the line ignore it. The live value is the same arithmetic
/// [portfolioValueProvider] already shows as the headline, so the chart's
/// last point and the number above it can never disagree either.
///
/// `collection_value_snapshots` keeps a row per collection per day, so every
/// portfolio in the switcher has its own line. A collection created today has
/// no history behind it yet — the cron starts recording it tonight — so the
/// series is just today's live point until then.
final portfolioValueSeriesProvider = FutureProvider<List<PortfolioValuePoint>>((
  ref,
) async {
  final collectionId = await ref.watch(selectedCollectionIdProvider.future);
  if (collectionId == null) return const [];

  final range = ref.watch(portfolioRangeProvider);
  final history = await ref
      .read(portfolioValueRepositoryProvider)
      .fetchValueSeries(range: range, collectionId: collectionId);

  final summary = await ref.watch(collectionSummaryProvider.future);
  if (summary.isEmpty) return history;

  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  final live = summary.totalValue;

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
  final summary = ref.watch(collectionSummaryProvider).valueOrNull;
  return (unique: summary?.uniqueCount ?? 0, total: summary?.totalCount ?? 0);
});

/// Re-exported so the Beranda widgets don't reach into the portfolio feature
/// for the card model they render.
typedef PortfolioCard = CardModel;
