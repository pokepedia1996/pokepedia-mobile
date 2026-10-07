import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/expansions/repository/expansions_repository.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/home/repository/models/portfolio_value.dart';
import 'package:pokepedia_mobile/features/home/usecase/portfolio_value_notifier.dart';
import 'package:pokepedia_mobile/features/search/repository/models/advanced_search_query.dart';
import 'package:pokepedia_mobile/features/search/repository/search_repository.dart';
import 'package:pokepedia_mobile/features/search/usecase/quick_search_notifier.dart';
import 'package:pokepedia_mobile/features/search/usecase/search_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/card_filtering.dart';

/// Both search pages now carry the expansion page's "Portofolio: …" switcher
/// and counters. The switcher only means something if the counts — and, on
/// Pencarian, the server-side "Dimiliki" filter — follow it.
const _me = AppUser(id: 'me', email: 'me@example.com');
const _binder = PortfolioTarget(name: 'Binder', listId: 'list-1');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

const _card = CardModel(
  id: 1,
  category: CardCategory.pokemon,
  nameId: 'Charizard',
  expansionCode: 'AC3D',
  packSlug: 'ac3d',
  collectorNumber: '021/172',
  rarity: 'R',
);

/// One card each, owned 2 in the main collection and 7 in the binder.
class _FakeExpansions implements ExpansionsRepository {
  @override
  Future<Map<int, int>> fetchOwnedQuantities(
    String userId,
    List<int> cardIds, {
    String? collectionId,
  }) async => {1: collectionId == 'list-1' ? 7 : 2};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeAdvanced implements SearchRepository {
  final collections = <String?>[];

  @override
  Future<SearchPage> search({
    required AdvancedSearchQuery query,
    int offset = 0,
    int limit = 40,
    String? collectionId,
  }) async {
    collections.add(collectionId);
    return const SearchPage(cards: [_card], total: 1, hasNext: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeQuick implements QuickSearchRepository {
  @override
  Future<FullSearchPage> searchAll(
    String query, {
    int offset = 0,
    int limit = QuickSearchRepository.searchBatchSize,
    CardSortOption? sort,
    Set<CardLanguage> languages = const {},
  }) async => const FullSearchPage(cards: [_card], total: 1, hasNext: false);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late _FakeAdvanced advanced;

  Future<ProviderContainer> container() async {
    advanced = _FakeAdvanced();
    final c = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        expansionsRepositoryProvider.overrideWithValue(_FakeExpansions()),
        searchRepositoryProvider.overrideWithValue(advanced),
        quickSearchRepositoryProvider.overrideWithValue(_FakeQuick()),
        portfolioTargetsProvider.overrideWithValue(const [
          PortfolioTarget.primary,
          _binder,
        ]),
        selectedCollectionIdProvider.overrideWith(
          (ref) async => ref.watch(selectedPortfolioProvider).listId ?? 'main',
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(authProvider.future);
    return c;
  }

  group('Pencarian', () {
    test(
      'counts and filters against the portfolio the switcher names',
      () async {
        final c = await container();
        final sub = c.listen(searchNotifierProvider, (_, __) {});
        addTearDown(sub.close);

        final notifier = c.read(searchNotifierProvider.notifier);
        notifier.setQuery('charizard');
        await notifier.search();

        expect(advanced.collections.last, 'main');
        expect(c.read(searchNotifierProvider).results.single.owned, 2);

        // Switching re-runs the search: "Dimiliki" is decided server-side.
        c.read(selectedPortfolioProvider.notifier).select(_binder);
        for (var i = 0; i < 20; i++) {
          if (advanced.collections.last == 'list-1' &&
              !c.read(searchNotifierProvider).loading) {
            break;
          }
          await pumpEventQueue();
        }

        expect(advanced.collections.last, 'list-1');
        expect(c.read(searchNotifierProvider).results.single.owned, 7);
      },
    );
  });

  group('hasil pencarian', () {
    test('a portfolio switch re-counts what is on screen', () async {
      final c = await container();
      final sub = c.listen(fullSearchProvider('charizard'), (_, __) {});
      addTearDown(sub.close);
      for (var i = 0; i < 20; i++) {
        if (!c.read(fullSearchProvider('charizard')).loading) break;
        await pumpEventQueue();
      }
      expect(c.read(fullSearchProvider('charizard')).cards.single.owned, 2);

      c.read(selectedPortfolioProvider.notifier).select(_binder);
      for (var i = 0; i < 20; i++) {
        if (c.read(fullSearchProvider('charizard')).cards.single.owned == 7) {
          break;
        }
        await pumpEventQueue();
      }
      expect(c.read(fullSearchProvider('charizard')).cards.single.owned, 7);
    });
  });
}
