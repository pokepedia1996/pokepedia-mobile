import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/pokemon_type.dart';
import '../../../shared/utils/card_filtering.dart';
import '../repository/search_repository.dart';

final searchRepositoryProvider = Provider((ref) {
  return SearchRepository(ref.read(supabaseClientProvider));
});

final searchFilterOptionsProvider = FutureProvider((ref) {
  return ref.read(searchRepositoryProvider).fetchFilterOptions();
});

/// [filters] carries every facet shared with the pack-detail/portfolio card
/// browsers (category, type, rarity, evolution stage, trainer subtype,
/// regulation mark) via the same [CardFilters] type. [packMarks] and
/// [illustrator] are search-specific, matching how `AdvancedSearchFilters`
/// extends the web's shared `CardFilters` with its own extra fields.
class SearchState {
  const SearchState({
    this.query = '',
    this.filters = const CardFilters(),
    this.packMarks = const {},
    this.illustrator = '',
    this.results = const [],
    this.hasSearched = false,
    this.loading = false,
  });

  final String query;
  final CardFilters filters;
  final Set<String> packMarks;
  final String illustrator;
  final List<CardModel> results;
  final bool hasSearched;
  final bool loading;

  bool get hasAnyFilter =>
      query.trim().isNotEmpty ||
      filters.activeCount > 0 ||
      packMarks.isNotEmpty ||
      illustrator.trim().isNotEmpty;

  SearchState copyWith({
    String? query,
    CardFilters? filters,
    Set<String>? packMarks,
    String? illustrator,
    List<CardModel>? results,
    bool? hasSearched,
    bool? loading,
  }) {
    return SearchState(
      query: query ?? this.query,
      filters: filters ?? this.filters,
      packMarks: packMarks ?? this.packMarks,
      illustrator: illustrator ?? this.illustrator,
      results: results ?? this.results,
      hasSearched: hasSearched ?? this.hasSearched,
      loading: loading ?? this.loading,
    );
  }
}

class SearchNotifier extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  Future<void> _run() async {
    if (!state.hasAnyFilter) {
      state = state.copyWith(results: [], loading: false, hasSearched: false);
      return;
    }
    state = state.copyWith(loading: true, hasSearched: true);
    final results = await ref
        .read(searchRepositoryProvider)
        .search(
          query: state.query,
          filters: state.filters,
          packMarks: state.packMarks,
          illustrator: state.illustrator,
        );
    state = state.copyWith(results: results, loading: false);
  }

  void setQuery(String value) {
    state = state.copyWith(query: value);
    _run();
  }

  void setIllustrator(String value) {
    state = state.copyWith(illustrator: value);
    _run();
  }

  void toggleRarity(String rarity) {
    state = state.copyWith(filters: state.filters.copyWith(rarities: _toggled(state.filters.rarities, rarity)));
    _run();
  }

  void toggleCategory(CardCategory category) {
    state = state.copyWith(filters: state.filters.copyWith(categories: _toggled(state.filters.categories, category)));
    _run();
  }

  void toggleType(PokemonType type) {
    state = state.copyWith(filters: state.filters.copyWith(types: _toggled(state.filters.types, type)));
    _run();
  }

  void toggleEvolutionStage(EvolutionStage stage) {
    state = state.copyWith(
      filters: state.filters.copyWith(evolutionStages: _toggled(state.filters.evolutionStages, stage)),
    );
    _run();
  }

  void toggleTrainerSubtype(TrainerSubtype subtype) {
    state = state.copyWith(
      filters: state.filters.copyWith(trainerSubtypes: _toggled(state.filters.trainerSubtypes, subtype)),
    );
    _run();
  }

  void toggleRegulationMark(String mark) {
    state = state.copyWith(
      filters: state.filters.copyWith(regulationMarks: _toggled(state.filters.regulationMarks, mark)),
    );
    _run();
  }

  void togglePackMark(String mark) {
    final next = {...state.packMarks};
    next.contains(mark) ? next.remove(mark) : next.add(mark);
    state = state.copyWith(packMarks: next);
    _run();
  }

  Set<T> _toggled<T>(Set<T> current, T value) {
    final next = {...current};
    if (!next.add(value)) next.remove(value);
    return next;
  }

  void reset() {
    state = const SearchState();
  }
}

final searchNotifierProvider = NotifierProvider<SearchNotifier, SearchState>(
  SearchNotifier.new,
);
