import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../home/usecase/portfolio_value_notifier.dart';
import '../../portfolio/usecase/portfolio_counter.dart';
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
    this.loading = true,
    this.loadingMore = false,
    this.failed = false,
    this.filters = const CardFilters(),
    this.ownership = OwnershipFilter.all,
    this.sort = CardSortOption.setDesc,
    this.viewMode = CardViewMode.grid,
    this.languages = const {},
  });

  final List<CardModel> cards;
  final int total;
  final bool hasNext;
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

  /// Which print languages to search, empty for all. Re-queries, as [sort]
  /// does: web sends it as `p_languages`, and narrowing a fetched page
  /// instead would hide matches that sit past it.
  final Set<CardLanguage> languages;

  FullSearchState copyWith({
    List<CardModel>? cards,
    int? total,
    bool? hasNext,
    bool? loading,
    bool? loadingMore,
    bool? failed,
    CardFilters? filters,
    OwnershipFilter? ownership,
    CardSortOption? sort,
    CardViewMode? viewMode,
    Set<CardLanguage>? languages,
  }) => FullSearchState(
    cards: cards ?? this.cards,
    total: total ?? this.total,
    hasNext: hasNext ?? this.hasNext,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    failed: failed ?? this.failed,
    filters: filters ?? this.filters,
    ownership: ownership ?? this.ownership,
    sort: sort ?? this.sort,
    viewMode: viewMode ?? this.viewMode,
    languages: languages ?? this.languages,
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
    // The counters answer for whichever portfolio the switcher names.
    // Deferred so the collection id derived from the switch has caught up —
    // read mid-notification, it still names the portfolio just left.
    ref.listen(
      selectedPortfolioProvider,
      (_, __) => Future.microtask(_refreshOwned),
    );
    ref.onDispose(() => _disposed = true);
    return const FullSearchState();
  }

  Future<void> _loadFirstPage() async {
    // Carried across the reload: the query changed, not what was asked of it.
    // Carried across the reload: the rows changed, not what was asked of them.
    final filters = state.filters;
    final ownership = state.ownership;
    final sort = state.sort;
    final viewMode = state.viewMode;
    final languages = state.languages;
    try {
      final page = await ref
          .read(quickSearchRepositoryProvider)
          .searchAll(arg, sort: sort, languages: languages);
      final cards = await _withOwned(page.cards);
      // A newer language or sort request started while this one was out;
      // its answer is the one that counts.
      if (languages != state.languages || sort != state.sort) return;
      state = FullSearchState(
        cards: cards,
        total: page.total,
        hasNext: page.hasNext,
        loading: false,
        filters: filters,
        ownership: ownership,
        sort: sort,
        viewMode: viewMode,
        languages: languages,
      );
    } catch (_) {
      if (languages != state.languages || sort != state.sort) return;
      state = FullSearchState(
        loading: false,
        failed: true,
        filters: filters,
        ownership: ownership,
        sort: sort,
        viewMode: viewMode,
        languages: languages,
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

  void setLanguages(Set<CardLanguage> languages) {
    if (languages.length == state.languages.length &&
        languages.containsAll(state.languages)) {
      return;
    }
    state = state.copyWith(languages: languages, loading: true, failed: false);
    unawaited(_loadFirstPage());
  }

  /// Patches one card's owned count after the counter has saved it, rather
  /// than re-running the whole search to learn a number already known.
  void setOwned(int cardId, int owned) {
    state = state.copyWith(
      cards: [
        for (final card in state.cards)
          card.id == cardId ? card.copyWith(owned: owned) : card,
      ],
    );
  }

  /// `search_cards_fuzzy` returns catalog rows, which know nothing about
  /// the viewer, so without this every result read as unowned: the counter
  /// would start at zero and the "Dimiliki" filter would match nothing.
  Future<List<CardModel>> _withOwned(List<CardModel> cards) =>
      withOwnedQuantities(ref, cards);

  /// Re-counts the rows already on screen against a newly picked portfolio.
  /// The search itself doesn't change, so it isn't re-run.
  Future<void> _refreshOwned() async {
    if (_disposed || state.cards.isEmpty) return;
    final cards = await _withOwned(state.cards);
    if (_disposed) return;
    state = state.copyWith(cards: cards);
  }

  /// The results go with the page, and a portfolio switch's re-count can
  /// land after the buyer has left it.
  bool _disposed = false;

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
          .searchAll(
            arg,
            offset: state.cards.length,
            sort: state.sort,
            languages: state.languages,
          );
      final more = await _withOwned(page.cards);
      state = state.copyWith(
        cards: [...state.cards, ...more],
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
