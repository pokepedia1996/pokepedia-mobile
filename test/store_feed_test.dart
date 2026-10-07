import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/market/repository/market_repository.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

/// A storefront used to load its 100 newest listings and search inside
/// them, so a shop with 2,000 answered "spinarak" with "Tidak ada kartu yang
/// cocok" while the card page listed that same shop's Spinarak. The search,
/// and the paging, belong to the server.
ListingModel _listing(int i, String name) => ListingModel(
  id: i,
  sellerId: 'seller-1',
  slug: 'listing-$i',
  side: ListingSide.ask,
  price: 5000,
  condition: CardCondition.nm,
  quantity: 1,
  card: CardModel(
    id: i,
    category: CardCategory.pokemon,
    nameId: name,
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '$i/165',
    rarity: 'C',
  ),
  storeSlug: 'airis',
  storeName: 'Airis Garage',
  isVerified: false,
  cityName: 'Tangerang Selatan',
  createdAt: DateTime(2026, 8, 1),
);

/// A 2,161-listing shop whose one Spinarak is the oldest of them.
class _FakeMarket implements MarketRepository {
  final asked = <({String? search, String side, int offset})>[];

  late final shop = [
    for (var i = 0; i < 2160; i++) _listing(i, 'Kartu $i'),
    _listing(2160, 'Spinarak'),
  ];

  @override
  Future<List<ListingModel>> fetchStoreListingsPage({
    required String sellerUserId,
    required String side,
    String? search,
    String? condition,
    String sort = 'created_desc',
    int offset = 0,
    int limit = MarketRepository.storeListingsPageSize,
  }) async {
    asked.add((search: search, side: side, offset: offset));
    final needle = (search ?? '').toLowerCase();
    final matches = [
      for (final l in shop)
        if (needle.isEmpty || l.card.name.toLowerCase().contains(needle)) l,
    ];
    return matches.skip(offset).take(limit).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late _FakeMarket market;

  ProviderContainer container() {
    market = _FakeMarket();
    final c = ProviderContainer(
      overrides: [marketRepositoryProvider.overrideWithValue(market)],
    );
    addTearDown(c.dispose);
    return c;
  }

  StoreFeedKey key({String search = ''}) => (
    sellerUserId: 'seller-1',
    side: 'ask',
    search: search,
    condition: null,
    sort: 'created_desc',
  );

  Future<StoreFeedState> settle(ProviderContainer c, StoreFeedKey k) async {
    final sub = c.listen(storeFeedProvider(k), (_, __) {});
    addTearDown(sub.close);
    for (var i = 0; i < 20 && c.read(storeFeedProvider(k)).loading; i++) {
      await pumpEventQueue();
    }
    return c.read(storeFeedProvider(k));
  }

  test('finds a card well past the newest hundred', () async {
    final c = container();
    final feed = await settle(c, key(search: 'spinarak'));

    expect(market.asked.single.search, 'spinarak');
    expect(feed.listings.map((l) => l.card.name), ['Spinarak']);
    expect(feed.hasNext, isFalse);
  });

  test('browsing pages on instead of stopping at a fixed count', () async {
    final c = container();
    final k = key();
    final first = await settle(c, k);
    expect(first.listings, hasLength(MarketRepository.storeListingsPageSize));
    expect(first.hasNext, isTrue);

    await c.read(storeFeedProvider(k).notifier).loadMore();
    final second = c.read(storeFeedProvider(k));
    expect(
      second.listings,
      hasLength(2 * MarketRepository.storeListingsPageSize),
    );
    expect(market.asked.last.offset, MarketRepository.storeListingsPageSize);
  });

  test('a page that lands after its search was replaced is dropped', () async {
    final c = container();
    final k = key();
    await settle(c, k);

    final notifier = c.read(storeFeedProvider(k).notifier);
    final pending = notifier.loadMore();
    await notifier.retry();
    await pending;

    // The retry's first page stands; the stale second page was not appended.
    expect(
      c.read(storeFeedProvider(k)).listings,
      hasLength(MarketRepository.storeListingsPageSize),
    );
  });
}
