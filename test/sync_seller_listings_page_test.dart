import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';
import 'package:pokepedia_mobile/features/seller/repository/seller_listings_repository.dart';
import 'package:pokepedia_mobile/features/seller/usecase/seller_listings_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';

/// The product list reads `get_seller_listings_page` and
/// `get_seller_listing_tab_counts`, web's `fetchSellerListingsPage` and
/// `fetchSellerListingTabCounts`.
Map<String, dynamic> _pageRow(String slug, {int price = 125000}) => {
  'slug': slug,
  'card_id': 7,
  'card_name': 'Charizard ex',
  'expansion_code': 'SV2a',
  'collector_number': '201/165',
  'image_url': null,
  'rarity': 'SAR',
  'variant_key': null,
  'variant': 'normal',
  'language': 'id',
  'condition': 'LP',
  'price': price,
  'quantity': 3,
  'qty_locked': 1,
  'status': 'open',
  'photo_urls': <String>[],
  'created_at': '2026-08-01T10:00:00+00:00',
  'updated_at': '2026-08-02T10:00:00+00:00',
  'expires_at': '2099-09-01T10:00:00+00:00',
  'archived_at': null,
  'auto_relist': true,
  'accepts_offers': false,
  'view_count': 42,
  'sold_count': 2,
};

const _me = AppUser(id: 'seller', email: 'seller@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

class _FakeRepo implements SellerListingsRepository {
  _FakeRepo(this.total);

  final int total;
  final offsets = <int>[];

  @override
  Future<SellerListingsPage> fetchListingsPage({
    required SellerListingBucket bucket,
    String query = '',
    ListingSort sort = const ListingSort(ListingSortCol.price),
    bool withOffers = false,
    int offset = 0,
    int limit = 30,
  }) async {
    offsets.add(offset);
    final end = (offset + limit).clamp(0, total);
    return SellerListingsPage(
      rows: [
        for (var i = offset; i < end; i++)
          SellerListing.fromRow(_pageRow('slug-$i')),
      ],
      totalCount: total,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SellerListing.fromRow on a page row', () {
    test('reads the flat card columns into the card', () {
      final listing = SellerListing.fromRow(_pageRow('abc'));

      expect(listing.id, isNull);
      expect(listing.slug, 'abc');
      expect(listing.card.id, 7);
      expect(listing.card.name, 'Charizard ex');
      expect(listing.card.expansionCode, 'SV2a');
      expect(listing.card.collectorNumber, '201/165');
      expect(listing.condition, CardCondition.lp);
      expect(listing.available, 2);
      expect(listing.viewCount, 42);
      expect(listing.bucket, SellerListingBucket.active);
    });

    test('a missing card name falls back the way web does', () {
      final row = _pageRow('abc')..['card_name'] = null;
      expect(SellerListing.fromRow(row).card.name, 'Kartu #7');
    });
  });

  group('SellerListingsPage.fromJson', () {
    test('carries the bucket-wide totals', () {
      final page = SellerListingsPage.fromJson({
        'rows': [_pageRow('a'), _pageRow('b')],
        'total_count': 120,
        'total_value': 9000000,
        'total_qty': 300,
        'offers_count': 4,
      });

      expect(page.rows.map((r) => r.slug), ['a', 'b']);
      expect(page.totalCount, 120);
      expect(page.totalValue, 9000000);
      expect(page.totalQty, 300);
      expect(page.offersCount, 4);
    });

    test('a row that will not parse is dropped, not the page', () {
      final broken = _pageRow('bad')..['card_id'] = 'not-a-number';
      final page = SellerListingsPage.fromJson({
        'rows': [_pageRow('a'), broken, 'junk'],
        'total_count': 3,
      });

      expect(page.rows.map((r) => r.slug), ['a']);
      expect(page.offersCount, 0);
    });

    test('the signed-out payload is an empty page', () {
      final page = SellerListingsPage.fromJson({
        'rows': <Object>[],
        'total_count': 0,
        'total_value': 0,
        'total_qty': 0,
        'offers_count': 0,
      });
      expect(page.rows, isEmpty);
      expect(page.totalCount, 0);
    });
  });

  group('bucket and sort mapping', () {
    test('tabs map to the RPC bucket values', () {
      expect(SellerListingBucket.active.rpcValue, 'active');
      expect(SellerListingBucket.inactive.rpcValue, 'inactive');
      expect(SellerListingBucket.archived.rpcValue, 'archive');
      expect(SellerListingBucket.draft.rpcValue, 'draft');
      expect(SellerListingBucket.preferences.rpcValue, isNull);
    });

    test('sort columns map to the RPC whitelist', () {
      expect(ListingSortCol.values.map((c) => c.rpcValue), [
        'cardName',
        'expansionCode',
        'collectorNumber',
        'condition',
        'price',
        'quantity',
        'viewCount',
      ]);
      expect(const ListingSort(ListingSortCol.price).rpcDirection, 'desc');
      expect(
        const ListingSort(ListingSortCol.price, ascending: true).rpcDirection,
        'asc',
      );
    });

    test('tab counts read by key, missing or junk as zero', () {
      final counts = parseSellerTabCounts({
        'active': 12,
        'inactive': 3,
        'archive': 'x',
      });
      expect(counts, {
        SellerListingBucket.active: 12,
        SellerListingBucket.inactive: 3,
        SellerListingBucket.archived: 0,
        SellerListingBucket.draft: 0,
      });
      expect(parseSellerTabCounts(null)[SellerListingBucket.active], 0);
    });
  });

  group('SellerListingsFeed', () {
    ProviderContainer container(_FakeRepo repo) {
      final c = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          sellerListingsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      c.listen(sellerListingsFeedProvider, (_, __) {});
      return c;
    }

    Future<void> settle(ProviderContainer c) async {
      await c.read(authProvider.future);
      await c.read(sellerListingsPageProvider.future);
      await Future<void>.delayed(Duration.zero);
    }

    test('pages past the first by offset until the total is reached', () async {
      final repo = _FakeRepo(70);
      final c = container(repo);
      await settle(c);

      var feed = c.read(sellerListingsFeedProvider);
      expect(feed.rows, hasLength(sellerListingsPageSize));
      expect(feed.totalCount, 70);
      expect(feed.hasMore, isTrue);

      await c.read(sellerListingsFeedProvider.notifier).loadMore();
      await c.read(sellerListingsFeedProvider.notifier).loadMore();
      feed = c.read(sellerListingsFeedProvider);
      expect(feed.rows, hasLength(70));
      expect(feed.hasMore, isFalse);
      expect(repo.offsets, [0, 30, 60]);

      await c.read(sellerListingsFeedProvider.notifier).loadMore();
      expect(repo.offsets, [0, 30, 60]);
    });

    test('a refresh drops back to the first page', () async {
      final repo = _FakeRepo(70);
      final c = container(repo);
      await settle(c);
      await c.read(sellerListingsFeedProvider.notifier).loadMore();
      expect(c.read(sellerListingsFeedProvider).rows, hasLength(60));

      c.invalidate(sellerListingsPageProvider);
      await settle(c);
      expect(
        c.read(sellerListingsFeedProvider).rows,
        hasLength(sellerListingsPageSize),
      );
    });
  });
}
