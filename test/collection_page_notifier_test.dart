import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/portfolio_repository.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/collection_page_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/card_filtering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    collectorNumber: '$id',
    rarity: 'C',
    owned: 1,
  ),
  collectionCardId: 'cc-$id',
);

/// Hands out queued pages in order, recording each request's sort.
class _ScriptedRepository extends PortfolioRepository {
  _ScriptedRepository(super.client, this.pages);

  final List<CollectionCardsPage> pages;
  final sorts = <CardSortOption>[];

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
    sorts.add(sort);
    return pages.removeAt(0);
  }
}

void main() {
  late SupabaseClient client;
  setUpAll(() => client = SupabaseClient('http://localhost:1', 'anon-key'));
  tearDownAll(() => client.dispose());

  Future<ProviderContainer> start(_ScriptedRepository repository) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        listsProvider.overrideWith((ref) async => const []),
        portfolioRepositoryProvider.overrideWithValue(repository),
        collectionFacetsProvider.overrideWith(
          (ref) async => const CollectionFacets(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(collectionPageProvider, (_, __) {});
    await container.read(authProvider.future);
    await pumpEventQueue();
    return container;
  }

  test('later pages append, skip repeats, and keep the first total', () async {
    final repository = _ScriptedRepository(client, [
      CollectionCardsPage(
        rows: [for (var i = 1; i <= collectionPageSize; i++) _row(i)],
        total: 50,
      ),
      // The second page repeats the first page's last row, and — like the
      // RPC — carries no total.
      CollectionCardsPage(rows: [_row(collectionPageSize), _row(49), _row(50)]),
    ]);
    final container = await start(repository);

    var state = container.read(collectionPageProvider);
    expect(state.rows.length, collectionPageSize);
    expect(state.total, 50);
    expect(state.hasNext, isTrue);

    await container.read(collectionPageProvider.notifier).loadMore();
    state = container.read(collectionPageProvider);
    expect(state.rows.length, 50);
    expect(state.rows.map((r) => r.collectionCardId).toSet().length, 50);
    expect(state.total, 50);
    expect(state.hasNext, isFalse);
  });

  test('a short first page has no next page', () async {
    final repository = _ScriptedRepository(client, [
      CollectionCardsPage(rows: [_row(1), _row(2)], total: 2),
    ]);
    final container = await start(repository);

    final state = container.read(collectionPageProvider);
    expect(state.loading, isFalse);
    expect(state.hasNext, isFalse);
  });

  test('changing the sort reloads from the first page', () async {
    final repository = _ScriptedRepository(client, [
      CollectionCardsPage(rows: [_row(1)], total: 1),
      CollectionCardsPage(rows: [_row(2)], total: 1),
    ]);
    final container = await start(repository);

    container.read(collectionSortProvider.notifier).state =
        CardSortOption.nameAsc;
    container.read(collectionPageProvider);
    await pumpEventQueue();

    expect(repository.sorts, [
      CardSortOption.priceDesc,
      CardSortOption.nameAsc,
    ]);
    expect(
      container.read(collectionPageProvider).rows.single.collectionCardId,
      'cc-2',
    );
  });
}
