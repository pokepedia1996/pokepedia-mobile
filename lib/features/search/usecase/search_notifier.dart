import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/catalog_language_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/pokemon_type.dart';
import '../../../shared/utils/card_filtering.dart';
import '../repository/models/advanced_search_query.dart';
import '../repository/search_repository.dart';

final searchRepositoryProvider = Provider((ref) {
  return SearchRepository(ref.read(supabaseClientProvider));
});

final searchFilterOptionsProvider = FutureProvider((ref) {
  final language = ref.watch(catalogLanguageProvider);
  return ref
      .read(searchRepositoryProvider)
      .fetchFilterOptions(language: language.raw);
});

/// The query the user is building plus the page it produced.
class SearchState {
  const SearchState({
    this.query = const AdvancedSearchQuery(),
    this.results = const [],
    this.total = 0,
    this.hasNext = false,
    this.hasSearched = false,
    this.loading = false,
    this.loadingMore = false,
  });

  final AdvancedSearchQuery query;
  final List<CardModel> results;

  /// Total matches server-side, which is usually larger than [results].
  final int total;
  final bool hasNext;
  final bool hasSearched;
  final bool loading;
  final bool loadingMore;

  bool get hasAnyFilter => query.hasAnyFilter;

  SearchState copyWith({
    AdvancedSearchQuery? query,
    List<CardModel>? results,
    int? total,
    bool? hasNext,
    bool? hasSearched,
    bool? loading,
    bool? loadingMore,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      total: total ?? this.total,
      hasNext: hasNext ?? this.hasNext,
      hasSearched: hasSearched ?? this.hasSearched,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
    );
  }
}

class SearchNotifier extends Notifier<SearchState> {
  /// Guards against an older in-flight search overwriting a newer one —
  /// every facet tap re-runs the query.
  int _generation = 0;
  Timer? _debounce;

  @override
  SearchState build() {
    ref.listen(catalogLanguageProvider, (_, __) => _rerunIfSearched());
    ref.onDispose(() => _debounce?.cancel());
    return const SearchState();
  }

  /// Re-runs only what's already on screen. Editing a facet doesn't search
  /// — the web form collects filters and searches when "Cari" is pressed,
  /// so a half-built query never fires a request.
  void _rerunIfSearched() {
    if (!state.hasSearched) return;
    _debounce?.cancel();
    unawaited(_search());
  }

  /// Runs the query the form currently holds. This is what "Cari" calls.
  Future<void> search() => _search();

  Future<void> _search() async {
    final query = state.query.copyWith(
      language: ref.read(catalogLanguageProvider).raw,
    );
    if (!query.hasAnyFilter) {
      state = state.copyWith(
        results: const [],
        total: 0,
        hasNext: false,
        loading: false,
        hasSearched: false,
      );
      return;
    }

    final generation = ++_generation;
    state = state.copyWith(loading: true, hasSearched: true);
    final page = await ref.read(searchRepositoryProvider).search(query: query);
    if (generation != _generation) return;

    state = state.copyWith(
      results: page.cards,
      total: page.total,
      hasNext: page.hasNext,
      loading: false,
    );
  }

  /// Appends the next page — the RPC pages server-side, so the facets stay
  /// applied across the whole catalog rather than just the first batch.
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasNext) return;

    final generation = _generation;
    state = state.copyWith(loadingMore: true);
    final page = await ref
        .read(searchRepositoryProvider)
        .search(
          query: state.query.copyWith(
            language: ref.read(catalogLanguageProvider).raw,
          ),
          offset: state.results.length,
        );
    if (generation != _generation) return;

    state = state.copyWith(
      results: [...state.results, ...page.cards],
      total: page.total,
      hasNext: page.hasNext,
      loadingMore: false,
    );
  }

  // --- Text inputs --------------------------------------------------------

  void setQuery(String value) {
    state = state.copyWith(query: state.query.copyWith(name: value));
  }

  void setIllustrator(String value) {
    state = state.copyWith(query: state.query.copyWith(illustrator: value));
  }

  // --- Facets -------------------------------------------------------------

  void toggleRarity(String rarity) =>
      _updateFilters((f) => f.copyWith(rarities: _toggled(f.rarities, rarity)));

  void toggleCategory(CardCategory category) => _updateFilters(
    (f) => f.copyWith(categories: _toggled(f.categories, category)),
  );

  void toggleType(PokemonType type) =>
      _updateFilters((f) => f.copyWith(types: _toggled(f.types, type)));

  void toggleEvolutionStage(EvolutionStage stage) => _updateFilters(
    (f) => f.copyWith(evolutionStages: _toggled(f.evolutionStages, stage)),
  );

  void toggleTrainerSubtype(TrainerSubtype subtype) => _updateFilters(
    (f) => f.copyWith(trainerSubtypes: _toggled(f.trainerSubtypes, subtype)),
  );

  void toggleRegulationMark(String mark) => _updateFilters(
    (f) => f.copyWith(regulationMarks: _toggled(f.regulationMarks, mark)),
  );

  void togglePackMark(String mark) {
    state = state.copyWith(
      query: state.query.copyWith(
        packMarks: _toggled(state.query.packMarks, mark),
      ),
    );
  }

  /// Select-all / clear-all for one series' expansions, like the web's
  /// series row in the expansion picker.
  void togglePackMarks(List<String> marks) {
    final next = {...state.query.packMarks};
    final allSelected = marks.every(next.contains);
    for (final mark in marks) {
      allSelected ? next.remove(mark) : next.add(mark);
    }
    state = state.copyWith(query: state.query.copyWith(packMarks: next));
  }

  void toggleWeaknessType(PokemonType type) {
    state = state.copyWith(
      query: state.query.copyWith(
        weaknessTypes: _toggled(state.query.weaknessTypes, type),
      ),
    );
  }

  void toggleResistanceType(PokemonType type) {
    state = state.copyWith(
      query: state.query.copyWith(
        resistanceTypes: _toggled(state.query.resistanceTypes, type),
      ),
    );
  }

  // --- Ranges -------------------------------------------------------------

  void setHpRange(int? min, int? max) {
    state = state.copyWith(
      query: state.query.copyWith(hpMin: () => min, hpMax: () => max),
    );
  }

  void setRetreatRange(int? min, int? max) {
    state = state.copyWith(
      query: state.query.copyWith(retreatMin: () => min, retreatMax: () => max),
    );
  }

  void setAttackCostRange(int? min, int? max) {
    state = state.copyWith(
      query: state.query.copyWith(
        attackCostMin: () => min,
        attackCostMax: () => max,
      ),
    );
  }

  // --- Sort & ownership ---------------------------------------------------

  void setSort(SearchSort sort) {
    state = state.copyWith(query: state.query.copyWith(sort: sort));
    _rerunIfSearched();
  }

  void setOwnership(OwnershipFilter ownership) {
    state = state.copyWith(query: state.query.copyWith(ownership: ownership));
    _rerunIfSearched();
  }

  void reset() {
    _generation++;
    state = const SearchState();
  }

  void _updateFilters(CardFilters Function(CardFilters) update) {
    state = state.copyWith(
      query: state.query.copyWith(filters: update(state.query.filters)),
    );
  }

  Set<T> _toggled<T>(Set<T> current, T value) {
    final next = {...current};
    if (!next.add(value)) next.remove(value);
    return next;
  }
}

final searchNotifierProvider = NotifierProvider<SearchNotifier, SearchState>(
  SearchNotifier.new,
);
