import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/market/repository/market_repository.dart';
import 'package:pokepedia_mobile/features/market/repository/models/market_page.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

/// The feed used to be one hardcoded page of 40 at `p_offset: 0` — nothing
/// could reach row 41. It pages by keyset cursor now, because a feed people
/// scroll while listings are being created would repeat or skip rows under
/// OFFSET.
ListingModel _listing(int id) => ListingModel(
  id: id,
  sellerId: 'seller-$id',
  slug: 'listing-$id',
  side: ListingSide.ask,
  price: 1000 * id,
  condition: CardCondition.nm,
  quantity: 1,
  card: const CardModel(
    id: 1,
    category: CardCategory.pokemon,
    nameId: 'Pikachu',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '025/165',
    rarity: 'Rare',
  ),
  storeSlug: 'toko',
  storeName: 'Toko',
  isVerified: false,
  cityName: 'Jakarta',
  createdAt: DateTime(2026, 9, 20).subtract(Duration(minutes: id)),
);

class _FakeRepo implements MarketRepository {
  _FakeRepo(this.pages);

  /// Pages handed out in order, one per call.
  final List<MarketListingsPage> pages;
  final cursors = <MarketCursor?>[];
  int calls = 0;

  @override
  Future<MarketListingsPage> fetchListings({
    required MarketBucket bucket,
    String query = '',
    MarketSort sort = MarketSort.createdDesc,
    MarketFilters filters = const MarketFilters(),
    MarketCursor? cursor,
    int limit = 40,
  }) async {
    cursors.add(cursor);
    final page = pages[calls.clamp(0, pages.length - 1)];
    calls++;
    return page;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MarketListingsPage _page(List<int> ids, {required bool hasNext}) {
  final listings = [for (final id in ids) _listing(id)];
  return MarketListingsPage(
    listings: listings,
    hasNext: hasNext,
    cursor: listings.isEmpty
        ? null
        : MarketCursor(
            id: listings.last.id,
            createdAt: listings.last.createdAt,
            price: listings.last.price,
          ),
  );
}

ProviderContainer _container(_FakeRepo repo) {
  final container = ProviderContainer(
    overrides: [marketRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<MarketListingsState> _settled(ProviderContainer c) async {
  c.listen(marketListingsProvider, (_, __) {});
  await Future<void>.delayed(Duration.zero);
  return c.read(marketListingsProvider);
}

void main() {
  test('loads the first page and reports there is more', () async {
    final repo = _FakeRepo([
      _page([1, 2], hasNext: true),
    ]);
    final state = await _settled(_container(repo));

    expect(state.loading, isFalse);
    expect(state.listings.map((l) => l.id), [1, 2]);
    expect(state.hasNext, isTrue);
    // The first call carries no cursor — it starts the feed.
    expect(repo.cursors.single, isNull);
  });

  test('appends the next page and advances the cursor', () async {
    final repo = _FakeRepo([
      _page([1, 2], hasNext: true),
      _page([3, 4], hasNext: false),
    ]);
    final container = _container(repo);
    await _settled(container);

    await container.read(marketListingsProvider.notifier).loadMore();
    final state = container.read(marketListingsProvider);

    expect(state.listings.map((l) => l.id), [1, 2, 3, 4]);
    expect(state.hasNext, isFalse);
    // Continued from the last row of page one, not from the start again.
    expect(repo.cursors.last?.id, 2);
  });

  test('stops asking once the server says there is no more', () async {
    final repo = _FakeRepo([
      _page([1], hasNext: false),
    ]);
    final container = _container(repo);
    await _settled(container);

    await container.read(marketListingsProvider.notifier).loadMore();
    await container.read(marketListingsProvider.notifier).loadMore();

    expect(repo.calls, 1);
  });

  test('a page emptied by the own-listings filter still advances', () async {
    // `hasNext` is decided before own listings are dropped, so a page that
    // filters down to nothing must not read as the end of the feed — and the
    // cursor has to move, or it would ask for the same rows forever.
    final repo = _FakeRepo([
      _page([1, 2], hasNext: true),
      MarketListingsPage(
        listings: const [],
        hasNext: true,
        cursor: MarketCursor(
          id: 9,
          createdAt: DateTime(2026, 9, 19),
          price: 500,
        ),
      ),
      _page([10], hasNext: false),
    ]);
    final container = _container(repo);
    await _settled(container);

    await container.read(marketListingsProvider.notifier).loadMore();
    expect(container.read(marketListingsProvider).hasNext, isTrue);

    await container.read(marketListingsProvider.notifier).loadMore();
    expect(repo.cursors.last?.id, 9);
    expect(container.read(marketListingsProvider).listings.map((l) => l.id), [
      1,
      2,
      10,
    ]);
  });

  test('a failed page keeps the rows already on screen', () async {
    final repo = _FakeRepo([
      _page([1, 2], hasNext: true),
    ]);
    final container = _container(repo);
    await _settled(container);

    repo.pages.clear();
    await container.read(marketListingsProvider.notifier).loadMore();
    final state = container.read(marketListingsProvider);

    expect(state.listings.map((l) => l.id), [1, 2]);
    expect(state.loadingMore, isFalse);
  });

  test('changing the tab starts a fresh feed', () async {
    final repo = _FakeRepo([
      _page([1, 2], hasNext: true),
      _page([7], hasNext: false),
    ]);
    final container = _container(repo);
    await _settled(container);

    container.read(bucketProvider.notifier).state = MarketBucket.buylist;
    final state = await _settled(container);

    // Not appended to the old tab's rows, and asked for without a cursor.
    expect(state.listings.map((l) => l.id), [7]);
    expect(repo.cursors.last, isNull);
  });
}
