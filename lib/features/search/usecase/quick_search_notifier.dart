import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../repository/quick_search_repository.dart';

export '../repository/quick_search_repository.dart'
    show QuickSearchResults, QuickSearchRepository, FullSearchPage;

final quickSearchRepositoryProvider = Provider(
  (ref) => QuickSearchRepository(ref.read(supabaseClientProvider)),
);

/// Suggestions for one query.
///
/// Keyed by the query and auto-disposed, so a search bar that is opened,
/// typed into and closed leaves nothing behind — but re-typing a query still
/// warm in the cache answers without a round trip.
final quickSearchProvider = FutureProvider.autoDispose
    .family<QuickSearchResults, String>((ref, query) {
      if (query.trim().length < QuickSearchRepository.minQueryLength) {
        return Future.value(QuickSearchResults.empty);
      }
      return ref.read(quickSearchRepositoryProvider).search(query);
    });

/// The full results list for one query — web's `/search?q=`.
///
/// Holds its own pages rather than a provider per offset: "muat lebih banyak"
/// appends, and re-fetching every page each time one more arrives is how a
/// long list gets slow.
class FullSearchState {
  const FullSearchState({
    this.cards = const [],
    this.total = 0,
    this.hasNext = false,
    this.correctedQuery,
    this.loading = true,
    this.loadingMore = false,
    this.failed = false,
    this.filters = const CardFilters(),
    this.ownership = OwnershipFilter.all,
    this.sort = CardSortOption.setDesc,
    this.viewMode = CardViewMode.grid,
  });

  final List<CardModel> cards;
  final int total;
  final bool hasNext;

  /// The spelling these results are actually for, when nothing matched what
  /// was typed.
  final String? correctedQuery;
  final bool loading;
  final bool loadingMore;
  final bool failed;

  /// Applied on the client over the rows already fetched, as the expansion
  /// detail page does — the facet lists come from those same rows, so the
  /// options only ever offer values that are actually there.
  final CardFilters filters;
  final OwnershipFilter ownership;

  /// The one control that does re-query: `p_sort` orders the whole result
  /// set, and sorting only the fetched page by price would put the cheapest
  /// of the first forty on top rather than the cheapest match.
  final CardSortOption sort;

  /// Grid or list. Presentation only — it never re-queries.
  final CardViewMode viewMode;

  FullSearchState copyWith({
    List<CardModel>? cards,
    int? total,
    bool? hasNext,
    String? correctedQuery,
    bool? loading,
    bool? loadingMore,
    bool? failed,
    CardFilters? filters,
    OwnershipFilter? ownership,
    CardSortOption? sort,
    CardViewMode? viewMode,
  }) => FullSearchState(
    cards: cards ?? this.cards,
    total: total ?? this.total,
    hasNext: hasNext ?? this.hasNext,
    correctedQuery: correctedQuery ?? this.correctedQuery,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    failed: failed ?? this.failed,
    filters: filters ?? this.filters,
    ownership: ownership ?? this.ownership,
    sort: sort ?? this.sort,
    viewMode: viewMode ?? this.viewMode,
  );
}

class FullSearchNotifier
    extends AutoDisposeFamilyNotifier<FullSearchState, String> {
  @override
  FullSearchState build(String query) {
    if (query.trim().length < QuickSearchRepository.minQueryLength) {
      return const FullSearchState(loading: false);
    }
    Future.microtask(_loadFirstPage);
    return const FullSearchState();
  }

  Future<void> _loadFirstPage() async {
    // Carried across the reload: the query changed, not what was asked of it.
    // Carried across the reload: the rows changed, not what was asked of them.
    final filters = state.filters;
    final ownership = state.ownership;
    final sort = state.sort;
    final viewMode = state.viewMode;
    try {
      final page = await ref
          .read(quickSearchRepositoryProvider)
          .searchAll(arg, sort: sort);
      state = FullSearchState(
        cards: page.cards,
        total: page.total,
        hasNext: page.hasNext,
        correctedQuery: page.correctedQuery,
        loading: false,
        filters: filters,
        ownership: ownership,
        sort: sort,
        viewMode: viewMode,
      );
    } catch (_) {
      state = FullSearchState(
        loading: false,
        failed: true,
        filters: filters,
        ownership: ownership,
        sort: sort,
        viewMode: viewMode,
      );
    }
  }

  /// Local: the rows are already here, the facets just narrow them.
  void setFilters(CardFilters filters) {
    state = state.copyWith(filters: filters);
  }

  void setOwnership(OwnershipFilter ownership) {
    state = state.copyWith(ownership: ownership);
  }

  void setSort(CardSortOption sort) {
    if (sort == state.sort) return;
    state = state.copyWith(sort: sort, loading: true, failed: false);
    unawaited(_loadFirstPage());
  }

  /// Local: the same rows, drawn differently.
  void setViewMode(CardViewMode viewMode) {
    if (viewMode == state.viewMode) return;
    state = state.copyWith(viewMode: viewMode);
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasNext) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await ref
          .read(quickSearchRepositoryProvider)
          // Paging continues on the corrected spelling when that is what the
          // first page answered with.
          .searchAll(
            state.correctedQuery ?? arg,
            offset: state.cards.length,
            sort: state.sort,
          );
      state = state.copyWith(
        cards: [...state.cards, ...page.cards],
        hasNext: page.hasNext,
        loadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(loadingMore: false, hasNext: false);
    }
  }

  Future<void> retry() async {
    state = state.copyWith(loading: true, failed: false, cards: const []);
    await _loadFirstPage();
  }
}

final fullSearchProvider =
    AutoDisposeNotifierProviderFamily<
      FullSearchNotifier,
      FullSearchState,
      String
    >(FullSearchNotifier.new);
