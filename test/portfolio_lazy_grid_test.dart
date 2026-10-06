import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/usecase/portfolio_value_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/presentation/portfolio_page.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/collection_page.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/portfolio_repository.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/card_filtering.dart';
import 'package:pokepedia_mobile/shared/widgets/card_grid_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The collection grid reads the server a page at a time, the way web's
/// Koleksi does: opening it fetches one page, and scrolling to the end of
/// that page asks for the next from where it stopped.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

CollectionCardRow _row(int id) => CollectionCardRow(
  card: CardModel(
    id: id,
    category: CardCategory.pokemon,
    nameId: 'Kartu $id',
    expansionCode: 'SV3',
    packSlug: 'sv3',
    collectorNumber: '$id/197',
    rarity: 'SAR',
    owned: 1,
  ),
  collectionCardId: 'cc-$id',
  cursorNum: -1,
);

/// Serves a collection of [size] rows the way `get_collection_cards` pages
/// it, and records what each request asked for.
/// Built outside the widget test's fake clock: the client starts its own
/// timers, which the test would otherwise report as left pending.
late final SupabaseClient _client;

class _FakeRepository extends PortfolioRepository {
  _FakeRepository(this.size) : super(_client);

  final int size;
  final requests = <CollectionCardRow?>[];

  late final _rows = [for (var i = 1; i <= size; i++) _row(i)];

  @override
  Future<CollectionCardsPage> fetchCollectionPage({
    required String? collectionId,
    required CardSortOption sort,
    required CardFilters filters,
    CollectionFacets facets = const CollectionFacets(),
    CollectionCardRow? after,
    int offset = 0,
    int limit = collectionPageSize,
  }) async {
    requests.add(after);
    final start = after == null ? 0 : _rows.indexOf(after) + 1;
    final end = (start + limit).clamp(0, _rows.length);
    return CollectionCardsPage(
      rows: _rows.sublist(start, end),
      total: after == null ? _rows.length : null,
    );
  }

  @override
  Future<CollectionSummary> fetchCollectionSummary(
    String? collectionId,
  ) async => CollectionSummary(
    totalValue: 0,
    uniqueCount: size,
    totalCount: size,
    valueNow: 0,
    value7dAgo: 0,
  );

  @override
  Future<CollectionFacets> fetchCollectionFacets(String? collectionId) async =>
      const CollectionFacets();
}

Future<_FakeRepository> _open(WidgetTester tester, {required int cards}) async {
  // A tall, narrowish surface, so a grid row is a few hundred pixels rather
  // than the ~600 the default 800x600 gives — the point here is how many
  // rows a scroll passes. Wider than a real phone only because the test
  // harness's square fallback font runs a tile's caption row over the edge
  // at phone widths.
  tester.view.physicalSize = const Size(500 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final repository = _FakeRepository(cards);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      listsProvider.overrideWith((ref) async => const []),
      portfolioRepositoryProvider.overrideWithValue(repository),
      portfolioValueSeriesProvider.overrideWith((ref) async => const []),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const PortfolioPage()),
    ),
  );
  // Not `pumpAndSettle`: the loaders animate forever, so settling is never
  // reached. A couple of frames is all the providers need.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return repository;
}

void main() {
  setUpAll(() => _client = SupabaseClient('http://localhost:1', 'anon-key'));
  tearDownAll(() => _client.dispose());

  testWidgets('opening the collection fetches one page, not all of it', (
    tester,
  ) async {
    final repository = await _open(tester, cards: 400);

    expect(repository.requests, [null]);
    final first = tester.widgetList<CardGridItem>(find.byType(CardGridItem));
    expect(first, isNotEmpty);
    expect(first.length, lessThanOrEqualTo(collectionPageSize));
  });

  testWidgets('scrolling to the end of a page fetches the next after it', (
    tester,
  ) async {
    final repository = await _open(tester, cards: 400);

    final seen = <int>{};
    void record() => seen.addAll(
      tester
          .widgetList<CardGridItem>(find.byType(CardGridItem))
          .map((t) => t.card.id),
    );

    record();
    expect(seen.length, lessThanOrEqualTo(collectionPageSize));

    for (var i = 0; i < 24; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pump(const Duration(milliseconds: 300));
      record();
    }

    expect(seen.length, greaterThan(collectionPageSize));
    // The second request continues from the first page's last row.
    expect(repository.requests.length, greaterThanOrEqualTo(2));
    expect(repository.requests[1]?.collectionCardId, 'cc-$collectionPageSize');
  });
}
