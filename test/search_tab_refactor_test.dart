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
import 'package:pokepedia_mobile/features/search/usecase/search_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/pack_model.dart';
import 'package:pokepedia_mobile/shared/widgets/app_bottom_nav.dart';
import 'package:pokepedia_mobile/shared/widgets/card_grid_item.dart';
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

PackModel _pack(int i) => PackModel(
  slug: 'e$i',
  name: 'Ekspansi $i',
  mark: 'E$i',
  series: 'Evolusi Mega',
  releaseDate: '2026-01-0$i',
  cardCount: 100,
);

Future<_FakeRepo> _pump(WidgetTester tester) async {
  final repo = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchRepositoryProvider.overrideWithValue(repo),
        seriesGroupsProvider.overrideWith(
          (ref) async => [
            SeriesGroup(series: 'Evolusi Mega', packs: [_pack(1), _pack(2)]),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
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

    testWidgets('typing hides the expansions and shows the results', (
      tester,
    ) async {
      final repo = await _pump(tester);

      await tester.enterText(find.byType(TextField).first, 'charizard');
      await tester.pump();
      // The catalog leaves on a 220ms transition, so it is still on screen
      // for a moment — fading out, not answering. What matters is that it is
      // gone before the request goes out, which the 300ms debounce means it
      // is: this wait is the animation, not the response.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(ExpansionsBrowser), findsNothing);

      // Debounced: nothing has gone out yet.
      expect(repo.searches, 0);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(repo.searches, 1);
      expect(find.byType(CardGridItem), findsWidgets);
    });

    testWidgets('one search per pause, not one per keystroke', (tester) async {
      final repo = await _pump(tester);
      final field = find.byType(TextField).first;

      for (final q in ['c', 'ch', 'cha', 'char']) {
        await tester.enterText(field, q);
        await tester.pump(const Duration(milliseconds: 80));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(repo.searches, 1);
    });

    testWidgets('clearing the box brings the expansions straight back', (
      tester,
    ) async {
      await _pump(tester);
      final field = find.byType(TextField).first;

      await tester.enterText(field, 'charizard');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionsBrowser), findsNothing);

      await tester.enterText(field, '');
      await tester.pump();
      // No round trip on the way back: an empty box is not a search that
      // found nothing.
      expect(find.byType(ExpansionsBrowser), findsOneWidget);
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
}
