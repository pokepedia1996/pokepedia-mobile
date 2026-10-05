import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../home/repository/models/portfolio_value.dart';
import '../../home/usecase/portfolio_value_notifier.dart';
import '../repository/models/collection_page.dart';
import '../repository/portfolio_repository.dart';
import 'portfolio_notifier.dart';

export '../repository/models/collection_page.dart';

/// Web's `SEARCH_DEBOUNCE_MS` — long enough that typing a name is one query,
/// not one per letter.
const _searchDebounce = Duration(milliseconds: 300);

/// Most valuable first. The collection is a portfolio rather than a
/// checklist, so what it is worth is the order that answers the question the
/// page is opened with.
final collectionSortProvider = StateProvider<CardSortOption>(
  (ref) => CardSortOption.priceDesc,
);

/// The facet chips. The search text lives in [collectionSearchProvider],
/// because the box sits above the page and the wishlist reads it too.
final collectionFiltersProvider = StateProvider<CardFilters>(
  (ref) => const CardFilters(),
);

/// [collectionSearchProvider], settled.
class _SettledSearch extends Notifier<String> {
  Timer? _timer;

  @override
  String build() {
    ref.listen<String>(collectionSearchProvider, (_, next) {
      _timer?.cancel();
      _timer = Timer(_searchDebounce, () => state = next.trim());
    });
    ref.onDispose(() => _timer?.cancel());
    return ref.read(collectionSearchProvider).trim();
  }
}

final _settledSearchProvider = NotifierProvider<_SettledSearch, String>(
  _SettledSearch.new,
);

/// The collection the selected target names. Null is the primary
/// collection, which every collection RPC resolves on its own.
String? _collectionIdOf(PortfolioTarget target) =>
    target.isPrimary ? null : target.listId;

/// Totals for the selected portfolio, whatever the grid is filtered to.
final collectionSummaryProvider = FutureProvider<CollectionSummary>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(CollectionSummary.empty);
  final target = ref.watch(selectedPortfolioProvider);
  return ref
      .read(portfolioRepositoryProvider)
      .fetchCollectionSummary(_collectionIdOf(target));
});

/// The filter options the selected portfolio actually holds.
final collectionFacetsProvider = FutureProvider<CollectionFacets>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return Future.value(const CollectionFacets());
  final target = ref.watch(selectedPortfolioProvider);
  return ref
      .read(portfolioRepositoryProvider)
      .fetchCollectionFacets(_collectionIdOf(target));
});

/// Everything that reads a collection through the paged RPCs. Takes the
/// caller's `invalidate`, so a widget and the ownership controller share it.
void invalidateCollectionViews(void Function(ProviderOrFamily) invalidate) {
  invalidate(collectionPageProvider);
  invalidate(collectionSummaryProvider);
  invalidate(collectionFacetsProvider);
}

class CollectionPageState {
  const CollectionPageState({
    this.rows = const [],
    this.total = 0,
    this.loading = true,
    this.loadingMore = false,
    this.hasNext = false,
    this.error = false,
  });

  final List<CollectionCardRow> rows;

  /// Matches for the current search and filters.
  final int total;

  /// The first page is in flight. Rows from before a filter change stay on
  /// screen meanwhile, so only an empty grid shows a loader.
  final bool loading;
  final bool loadingMore;
  final bool hasNext;
  final bool error;

  CollectionPageState copyWith({
    List<CollectionCardRow>? rows,
    int? total,
    bool? loading,
    bool? loadingMore,
    bool? hasNext,
    bool? error,
  }) {
    return CollectionPageState(
      rows: rows ?? this.rows,
      total: total ?? this.total,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasNext: hasNext ?? this.hasNext,
      error: error ?? this.error,
    );
  }
}

typedef _PageQuery = ({
  String? collectionId,
  CardSortOption sort,
  CardFilters filters,
});

/// The Koleksi grid, a page at a time — ports web's `useServerCardPage`.
///
/// Rebuilt by any change to the portfolio, sort, filters or settled search,
/// since each is a different result set and the old cursor means nothing in
/// the new one.
class CollectionPageNotifier extends Notifier<CollectionPageState> {
  /// Bumped on every rebuild, so a response to an older query never lands
  /// over a newer one.
  int _generation = 0;
  _PageQuery? _query;
  String? _ownerKey;

  @override
  CollectionPageState build() {
    final user = ref.watch(authProvider).valueOrNull;
    final target = ref.watch(selectedPortfolioProvider);
    final sort = ref.watch(collectionSortProvider);
    final filters = ref.watch(collectionFiltersProvider);
    final search = ref.watch(_settledSearchProvider);

    final generation = ++_generation;
    if (user == null) return const CollectionPageState(loading: false);

    final query = (
      collectionId: _collectionIdOf(target),
      sort: sort,
      filters: filters.copyWith(search: search),
    );
    _query = query;

    // Another user's or another list's rows must not linger under this one's
    // title; the same collection re-sorted can keep its rows until the new
    // page lands.
    final ownerKey = '${user.id}:${target.listId}';
    final previous = stateOrNull;
    final keepRows = previous != null && ownerKey == _ownerKey;
    _ownerKey = ownerKey;

    Future.microtask(() => _loadFirst(generation, query));
    return keepRows
        ? previous.copyWith(loading: true, loadingMore: false, error: false)
        : const CollectionPageState();
  }

  CollectionFacets get _facets =>
      ref.read(collectionFacetsProvider).valueOrNull ??
      const CollectionFacets();

  Future<void> _loadFirst(int generation, _PageQuery query) async {
    try {
      final page = await ref
          .read(portfolioRepositoryProvider)
          .fetchCollectionPage(
            collectionId: query.collectionId,
            sort: query.sort,
            filters: query.filters,
            facets: _facets,
          );
      if (generation != _generation) return;
      final total = page.total ?? page.rows.length;
      state = CollectionPageState(
        rows: page.rows,
        total: total,
        loading: false,
        hasNext: _hasNext(page.rows.length, page.rows.length, total),
      );
    } catch (error, stack) {
      if (kDebugMode) debugPrint('[portfolio] collection page: $error\n$stack');
      if (generation != _generation) return;
      state = const CollectionPageState(loading: false, error: true);
    }
  }

  /// Appends the next page. Safe to call on every scroll frame — it returns
  /// immediately unless there is another page and nothing already in flight.
  Future<void> loadMore() async {
    final query = _query;
    if (query == null || state.loading || state.loadingMore) return;
    if (!state.hasNext || state.rows.isEmpty) return;

    final generation = _generation;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await ref
          .read(portfolioRepositoryProvider)
          .fetchCollectionPage(
            collectionId: query.collectionId,
            sort: query.sort,
            filters: query.filters,
            facets: _facets,
            after: state.rows.last,
            offset: state.rows.length,
          );
      if (generation != _generation) return;

      final seen = {for (final row in state.rows) row.collectionCardId};
      final rows = [
        ...state.rows,
        for (final row in page.rows)
          if (seen.add(row.collectionCardId)) row,
      ];
      state = state.copyWith(
        rows: rows,
        loadingMore: false,
        hasNext: _hasNext(page.rows.length, rows.length, state.total),
      );
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('[portfolio] collection next page: $error\n$stack');
      }
      // The rows already on screen stay; scrolling again retries the page.
      if (generation != _generation) return;
      state = state.copyWith(loadingMore: false);
    }
  }

  /// What the error state's "Coba lagi" calls.
  void retry() => ref.invalidateSelf();

  /// A short page is the last one; a full one is too if it reached the
  /// count the first page reported.
  static bool _hasNext(int pageLength, int loaded, int total) =>
      pageLength >= collectionPageSize && loaded < total;
}

final collectionPageProvider =
    NotifierProvider<CollectionPageNotifier, CollectionPageState>(
      CollectionPageNotifier.new,
    );
