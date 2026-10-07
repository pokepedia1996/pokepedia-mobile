import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/repository/expansions_repository.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/home/usecase/portfolio_value_notifier.dart';
import 'package:pokepedia_mobile/features/search/usecase/quick_search_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/card_filtering.dart';
import 'package:pokepedia_mobile/shared/widgets/card_filter_bar.dart';

const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

CardModel _card(int id, CardLanguage language) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: 'Budew',
  expansionCode: 'SV8A',
  packSlug: 'sv8a',
  collectorNumber: '001/187',
  rarity: 'C',
  language: language,
);

/// Answers with whatever languages it was asked for, and remembers them.
class _FakeSearch implements QuickSearchRepository {
  final asked = <Set<CardLanguage>>[];

  @override
  Future<FullSearchPage> searchAll(
    String query, {
    int offset = 0,
    int limit = QuickSearchRepository.searchBatchSize,
    CardSortOption? sort,
    Set<CardLanguage> languages = const {},
  }) async {
    asked.add(languages);
    final langs = languages.isEmpty ? CardLanguage.values : languages;
    final cards = [for (final l in langs) _card(l.index + 1, l)];
    return FullSearchPage(cards: cards, total: cards.length, hasNext: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeExpansions implements ExpansionsRepository {
  String? askedCollection;

  @override
  Future<Map<int, int>> fetchOwnedQuantities(
    String userId,
    List<int> cardIds, {
    String? collectionId,
  }) async {
    askedCollection = collectionId;
    return {1: 3};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late _FakeSearch search;
  late _FakeExpansions expansions;

  ProviderContainer container() {
    search = _FakeSearch();
    expansions = _FakeExpansions();
    final c = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        quickSearchRepositoryProvider.overrideWithValue(search),
        expansionsRepositoryProvider.overrideWithValue(expansions),
        selectedCollectionIdProvider.overrideWith((ref) async => 'col-1'),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<FullSearchState> settle(ProviderContainer c) async {
    for (
      var i = 0;
      i < 20 && c.read(fullSearchProvider('budew')).loading;
      i++
    ) {
      await pumpEventQueue();
    }
    return c.read(fullSearchProvider('budew'));
  }

  test('results know what the buyer owns, from the pointed-at shelf', () async {
    final c = container();
    await c.read(authProvider.future);
    final sub = c.listen(fullSearchProvider('budew'), (_, __) {});
    addTearDown(sub.close);

    final state = await settle(c);
    // Catalog rows know nothing about the viewer; without this every result
    // read as unowned and the counter started at zero.
    expect(state.cards.firstWhere((card) => card.id == 1).owned, 3);
    expect(state.cards.firstWhere((card) => card.id == 2).owned, 0);
    expect(expansions.askedCollection, 'col-1');
  });

  test(
    'a language re-queries the server rather than narrowing the page',
    () async {
      final c = container();
      await c.read(authProvider.future);
      final sub = c.listen(fullSearchProvider('budew'), (_, __) {});
      addTearDown(sub.close);
      await settle(c);

      c.read(fullSearchProvider('budew').notifier).setLanguages({
        CardLanguage.jp,
      });
      final state = await settle(c);

      expect(search.asked.last, {CardLanguage.jp});
      expect(state.languages, {CardLanguage.jp});
      expect(state.cards.map((card) => card.language), [CardLanguage.jp]);
    },
  );

  test('setOwned patches one tile in place', () async {
    final c = container();
    await c.read(authProvider.future);
    final sub = c.listen(fullSearchProvider('budew'), (_, __) {});
    addTearDown(sub.close);
    await settle(c);

    final calls = search.asked.length;
    c.read(fullSearchProvider('budew').notifier).setOwned(2, 5);
    final state = c.read(fullSearchProvider('budew'));
    expect(state.cards.firstWhere((card) => card.id == 2).owned, 5);
    expect(search.asked.length, calls, reason: 'no re-run of the search');
  });

  Widget bar({
    Set<CardLanguage> languages = const {},
    ValueChanged<Set<CardLanguage>>? onLanguagesChanged,
  }) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: CardFilterBar(
          // One card, so the Kategori section has an option and is drawn.
          cards: [_card(1, CardLanguage.id)],
          filters: const CardFilters(),
          onFiltersChanged: (_) {},
          sortBy: CardSortOption.setDesc,
          onSortChanged: (_) {},
          viewMode: CardViewMode.grid,
          onViewModeChanged: (_) {},
          showSearch: false,
          languages: languages,
          onLanguagesChanged: onLanguagesChanged ?? (_) {},
        ),
      ),
    ),
  );

  testWidgets('Bahasa is the first section inside the filter panel', (
    tester,
  ) async {
    Set<CardLanguage>? picked;
    await tester.pumpWidget(bar(onLanguagesChanged: (v) => picked = v));

    // Tucked into the panel, not on the bar itself.
    expect(find.text('Bahasa'), findsNothing);

    await tester.tap(find.text('Filter'));
    await tester.pump();
    final bahasa = tester.getTopLeft(find.text('Bahasa'));
    expect(bahasa.dy, lessThan(tester.getTopLeft(find.text('Kategori')).dy));

    // Three chips splitting the row evenly, as in the market filter.
    final widths = [
      for (final label in ['ID', 'EN', 'JP'])
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .width,
    ];
    expect(widths.toSet().length, 1);

    await tester.tap(find.text('EN'));
    expect(picked, {CardLanguage.en});
  });

  testWidgets('a chosen language counts as a filter and clears with them', (
    tester,
  ) async {
    Set<CardLanguage>? picked;
    await tester.pumpWidget(
      bar(languages: {CardLanguage.jp}, onLanguagesChanged: (v) => picked = v),
    );
    await tester.tap(find.text('Filter'));
    await tester.pump();

    final clear = find.text('Hapus filter (1)');
    expect(clear, findsOneWidget);
    await tester.tap(clear);
    expect(picked, isEmpty);
  });

  testWidgets('pages that pass no language handler show no row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CardFilterBar(
            cards: const [],
            filters: const CardFilters(),
            onFiltersChanged: (_) {},
            sortBy: CardSortOption.setDesc,
            onSortChanged: (_) {},
            viewMode: CardViewMode.grid,
            onViewModeChanged: (_) {},
            showSearch: false,
          ),
        ),
      ),
    );
    expect(find.text('Bahasa'), findsNothing);
  });
}
