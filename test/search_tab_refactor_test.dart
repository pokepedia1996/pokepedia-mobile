import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/expansions_page.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/search/presentation/advanced_search_page.dart';
import 'package:pokepedia_mobile/features/search/repository/models/advanced_search_query.dart';
import 'package:pokepedia_mobile/features/search/repository/search_repository.dart';
import 'package:pokepedia_mobile/features/search/usecase/quick_search_notifier.dart';
import 'package:pokepedia_mobile/features/search/usecase/search_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/pack_model.dart';
import 'package:pokepedia_mobile/shared/widgets/app_bottom_nav.dart';
import 'package:pokepedia_mobile/shared/widgets/card_grid_item.dart';
import 'package:pokepedia_mobile/shared/widgets/quick_search_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Pencarian tab absorbed the Ekspansi tab. It has to be both things
/// at once: the catalog when nothing is being asked for, and the answer when
/// something is.
class _FakeRepo extends SearchRepository {
  _FakeRepo._(this.client) : super(client);

  /// `autoRefreshToken: false` matters: a default client starts GoTrue's
  /// refresh timer, and `testWidgets` fails on a timer still pending when
  /// the tree goes away — before any tear-down gets the chance to stop it.
  /// Nothing here authenticates, so there is nothing to refresh.
  factory _FakeRepo() => _FakeRepo._(
    SupabaseClient(
      'http://localhost:1',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
  );

  final SupabaseClient client;
  int searches = 0;

  @override
  Future<SearchPage> search({
    required AdvancedSearchQuery query,
    int offset = 0,
    int limit = 40,
    String? collectionId,
  }) async {
    searches++;
    return SearchPage(
      cards: [
        const CardModel(
          id: 7,
          category: CardCategory.pokemon,
          nameId: 'Charizard ex',
          expansionCode: 'MA6',
          packSlug: 'ma6',
          collectorNumber: '001/203',
          rarity: 'SAR',
        ),
      ],
      total: 1,
      hasNext: false,
    );
  }

  @override
  Future<SearchFilterOptions> fetchFilterOptions({
    String language = 'id',
  }) async => const SearchFilterOptions(
    rarities: [],
    expansions: [],
    categories: [],
    types: [],
    evolutionStages: [],
    trainerSubtypes: [],
    regulationMarks: [],
  );
}

/// The top bar's quick search, answering with nothing — what matters here is
/// that it is the one being asked, not the advanced search.
class _FakeQuick implements QuickSearchRepository {
  final queries = <String>[];

  @override
  Future<QuickSearchResults> search(String query) async {
    queries.add(query);
    return QuickSearchResults.empty;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

PackModel _pack(int i) => PackModel(
  slug: 'e$i',
  name: 'Ekspansi $i',
  mark: 'E$i',
  series: 'Evolusi Mega',
  releaseDate: '2026-01-0$i',
  cardCount: 100,
);

Future<_FakeRepo> _pump(WidgetTester tester, {ThemeData? theme}) async {
  final repo = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchRepositoryProvider.overrideWithValue(repo),
        quickSearchRepositoryProvider.overrideWithValue(_FakeQuick()),
        seriesGroupsProvider.overrideWith(
          (ref) async => [
            SeriesGroup(series: 'Evolusi Mega', packs: [_pack(1), _pack(2)]),
          ],
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: const AdvancedSearchPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return repo;
}

void main() {
  group('navigation', () {
    test('Ekspansi is gone and Jual took its place', () {
      expect(AppBottomNav.tabPaths, isNot(contains(Routes.expansions)));
      expect(AppBottomNav.tabPaths, contains(Routes.seller));
      expect(AppBottomNav.items.map((i) => i.label), [
        'Beranda',
        'Pencarian',
        'Koleksi',
        'Market',
        'Jual',
        'Akun',
      ]);
      // The two lists are indexed against each other by the shell.
      expect(AppBottomNav.items.length, AppBottomNav.tabPaths.length);
    });
  });

  group('the search tab', () {
    testWidgets('shows the expansions when nothing is being searched for', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byType(ExpansionsBrowser), findsOneWidget);
      expect(find.byType(CardGridItem), findsNothing);
    });

    testWidgets('the top bar is Beranda\'s quick search, not the form', (
      tester,
    ) async {
      final repo = await _pump(tester);

      // The same field Beranda carries, suggestions and all.
      expect(find.byType(QuickSearchField), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(QuickSearchField),
          matching: find.byType(TextField),
        ),
        'charizard',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // It no longer drives the advanced search: no query went out, and the
      // catalog under it stays where it was.
      expect(repo.searches, 0);
      expect(find.byType(ExpansionsBrowser), findsOneWidget);
    });

    testWidgets('the panel\'s own name field runs the advanced search', (
      tester,
    ) async {
      final repo = await _pump(tester);

      await tester.tap(find.bySemanticsLabel('Buka filter pencarian'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Cari nama kartu...'),
        'charizard',
      );
      // A frame for the form to rebuild with the typed name, as one always
      // passes between a user's last keystroke and the submit.
      await tester.pump();
      // Submitted from the field — the same `_submit` the Cari button calls,
      // without depending on the button being on screen in a short surface.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(repo.searches, 1);
      expect(find.byType(CardGridItem), findsWidgets);
    });

    testWidgets('the filter panel opens and closes from the one button', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Filter Pencarian'), findsNothing);
      expect(find.byType(ExpansionsBrowser), findsOneWidget);

      // By label, not by position: the expansions underneath are a pile of
      // InkWells too, and "the last one" was one of them.
      await tester.tap(find.bySemanticsLabel('Buka filter pencarian'));
      // Settled, not a single frame: the panel drops in over 220ms and the
      // catalog fades out under it, so both are briefly on screen together.
      await tester.pumpAndSettle();
      expect(find.text('Filter Pencarian'), findsOneWidget);
      // The panel takes the body, so the catalog is not behind it.
      expect(find.byType(ExpansionsBrowser), findsNothing);

      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('Filter Pencarian'), findsNothing);
      expect(find.byType(ExpansionsBrowser), findsOneWidget);
    });
  });

  group('the filter button', () {
    // Built inside each test: the theme loads Google Fonts, which only works
    // within a running test.
    for (final dark in [false, true]) {
      testWidgets('its close cross shows against its fill in '
          '${dark ? 'dark' : 'light'} mode', (tester) async {
        await _pump(tester, theme: dark ? AppTheme.dark : AppTheme.light);
        await tester.tap(find.bySemanticsLabel('Buka filter pencarian'));
        await tester.pumpAndSettle();

        final button = find.bySemanticsLabel('Tutup filter pencarian');
        final cross = tester.widget<Icon>(
          find.descendant(of: button, matching: find.byType(Icon)),
        );
        final fill =
            (tester
                        .widget<AnimatedContainer>(
                          find.descendant(
                            of: button,
                            matching: find.byType(AnimatedContainer),
                          ),
                        )
                        .decoration!
                    as BoxDecoration)
                .color!;

        // Dark mode turns the open fill near-white; a fixed white cross on
        // it vanished. The two must stay well apart in brightness.
        final gap = (cross.color!.computeLuminance() - fill.computeLuminance())
            .abs();
        expect(gap, greaterThan(0.4));
      });
    }
  });
}
