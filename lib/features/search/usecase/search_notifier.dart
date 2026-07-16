import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/card_model.dart';
import '../repository/search_repository.dart';

final searchRepositoryProvider = Provider((ref) => SearchRepository());

final searchFilterOptionsProvider = FutureProvider((ref) {
  return ref.read(searchRepositoryProvider).fetchFilterOptions();
});

class SearchState {
  const SearchState({
    this.query = '',
    this.selectedRarities = const {},
    this.selectedPackMarks = const {},
    this.results = const [],
    this.hasSearched = false,
    this.loading = false,
  });

  final String query;
  final Set<String> selectedRarities;
  final Set<String> selectedPackMarks;
  final List<CardModel> results;
  final bool hasSearched;
  final bool loading;

  bool get hasAnyFilter =>
      query.trim().isNotEmpty ||
      selectedRarities.isNotEmpty ||
      selectedPackMarks.isNotEmpty;

  SearchState copyWith({
    String? query,
    Set<String>? selectedRarities,
    Set<String>? selectedPackMarks,
    List<CardModel>? results,
    bool? hasSearched,
    bool? loading,
  }) {
    return SearchState(
      query: query ?? this.query,
      selectedRarities: selectedRarities ?? this.selectedRarities,
      selectedPackMarks: selectedPackMarks ?? this.selectedPackMarks,
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
          rarities: state.selectedRarities,
          packMarks: state.selectedPackMarks,
        );
    state = state.copyWith(results: results, loading: false);
  }

  void setQuery(String value) {
    state = state.copyWith(query: value);
    _run();
  }

  void toggleRarity(String rarity) {
    final next = {...state.selectedRarities};
    next.contains(rarity) ? next.remove(rarity) : next.add(rarity);
    state = state.copyWith(selectedRarities: next);
    _run();
  }

  void togglePackMark(String mark) {
    final next = {...state.selectedPackMarks};
    next.contains(mark) ? next.remove(mark) : next.add(mark);
    state = state.copyWith(selectedPackMarks: next);
    _run();
  }

  void reset() {
    state = const SearchState();
  }
}

final searchNotifierProvider = NotifierProvider<SearchNotifier, SearchState>(
  SearchNotifier.new,
);
