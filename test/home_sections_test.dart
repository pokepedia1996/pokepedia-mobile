import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/catalog_language_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/home_banner_carousel.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/latest_releases_section.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/store_shelves_section.dart';
import 'package:pokepedia_mobile/features/home/repository/home_repository.dart';
import 'package:pokepedia_mobile/features/home/repository/models/store_shelf.dart';
import 'package:pokepedia_mobile/features/home/usecase/home_notifier.dart';
import 'package:pokepedia_mobile/features/home/usecase/store_shelves_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';
import 'package:pokepedia_mobile/shared/models/pack_model.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';

/// Beranda's browsing sections: the banners, the newest sets with the
/// collection's progress through them, and the store shelves that load as
/// the page is scrolled.
Widget _app(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

const _pack = PackModel(
  slug: 'ma6',
  name: '30th Celebration',
  mark: 'MA6',
  series: 'Mega',
  releaseDate: '2026-11-01',
  cardCount: 203,
);

StoreModel _store(String name, {double? positive, int? ratings}) => StoreModel(
  handle: name.toLowerCase().replaceAll(' ', '-'),
  storeName: name,
  tagline: '',
  activeListingCount: 5,
  cityName: 'Kota Depok',
  isVerified: false,
  topRated: false,
  itemsSoldCount: 0,
  followersCount: 0,
  userId: 'u-$name',
  positivePct: positive,
  feedbackScore: ratings,
);

ListingModel _listing(int i, int price) => ListingModel(
  id: i,
  sellerId: 's',
  slug: 'l$i',
  side: ListingSide.ask,
  price: price,
  condition: CardCondition.nm,
  quantity: 1,
  acceptsOffers: false,
  card: CardModel(
    id: i,
    category: CardCategory.pokemon,
    nameId: 'Kartu $i',
    expansionCode: 'MA2',
    packSlug: 'ma2',
    collectorNumber: '001/103',
    rarity: 'Rare',
  ),
  storeSlug: 'menara-tcg',
  storeName: 'Menara TCG',
  isVerified: false,
  cityName: 'Kota Depok',
  createdAt: DateTime(2026, 11, 20),
);

StoreShelf _shelf(String name, {int listings = 5}) => StoreShelf(
  store: _store(name, positive: 98, ratings: 32),
  listings: [for (var i = 0; i < listings; i++) _listing(i, 1000 * (i + 1))],
);

/// Hands out pages of shelves; [failNext] makes the next read throw.
class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository(this.pages);

  final List<StoreShelfPage> pages;
  final offsets = <int>[];
  bool failNext = false;
  int _served = 0;

  @override
  Future<StoreShelfPage> fetchStoreShelves({
    int offset = 0,
    int limit = 4,
  }) async {
    offsets.add(offset);
    if (failNext) {
      failNext = false;
      throw Exception('offline');
    }
    return pages[_served++];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('release card', () {
    testWidgets('shows how far the collection is through the set', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const IntrinsicHeight(child: ReleaseCard(pack: _pack, owned: 41))),
      );
      expect(find.text('MA6'), findsOneWidget);
      expect(find.text('30th Celebration'), findsOneWidget);
      expect(find.text('41/203'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);
    });

    testWidgets('signed out, it counts the set instead', (tester) async {
      await tester.pumpWidget(
        _app(const IntrinsicHeight(child: ReleaseCard(pack: _pack))),
      );
      expect(find.text('203 kartu'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('the section lists the newest sets with their progress', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const LatestReleasesSection(),
          overrides: [
            latestReleasesProvider.overrideWith((ref) async => [_pack]),
            latestReleaseOwnedProvider.overrideWith((ref) async => {'ma6': 1}),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Jelajahi Rilis Terbaru'), findsOneWidget);
      expect(find.text('Lihat Semua'), findsOneWidget);
      expect(find.text('1/203'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    });
  });

  group('store shelf', () {
    testWidgets('names the store and shows its newest listings', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(StoreShelfTile(shelf: _shelf('Menara TCG'))),
      );
      expect(find.text('Menara TCG'), findsOneWidget);
      expect(find.text('32'), findsOneWidget);
      expect(find.text('98% positif · Kota Depok'), findsOneWidget);
      // No logo: its initials stand in.
      expect(find.text('MT'), findsOneWidget);
      for (final price in [
        'Rp1.000',
        'Rp2.000',
        'Rp3.000',
        'Rp4.000',
        'Rp5.000',
      ]) {
        expect(find.text(price), findsOneWidget);
      }
    });

    testWidgets('a short shelf keeps its tiles the usual size', (tester) async {
      tester.view.physicalSize = const Size(430 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(StoreShelfTile(shelf: _shelf('Menara TCG', listings: 2))),
      );
      expect(find.text('Rp2.000'), findsOneWidget);
      expect(find.text('Rp3.000'), findsNothing);
      // A fifth of the shelf, less its padding and gaps, as with five
      // (pumped bare, without the section's side padding).
      final width = tester.getSize(find.byType(AspectRatio).first).width;
      expect(width, closeTo((430 - 20 - 4 * 8) / 5, 0.5));
    });
  });

  group('store shelves', () {
    test('pages through the directory until it runs out', () async {
      final repo = _FakeHomeRepository([
        StoreShelfPage(shelves: [_shelf('A')], nextOffset: 4, hasMore: true),
        StoreShelfPage(shelves: [_shelf('B')], nextOffset: 6, hasMore: false),
      ]);
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(storeShelvesProvider.future);
      final notifier = container.read(storeShelvesProvider.notifier);
      await notifier.loadMore();
      await notifier.loadMore();

      final state = container.read(storeShelvesProvider).value!;
      expect(state.shelves.map((s) => s.store.storeName), ['A', 'B']);
      expect(state.hasMore, isFalse);
      // The page after the last: never asked for.
      expect(repo.offsets, [0, 4]);
    });

    test('a failed page waits for a retry instead of refiring', () async {
      final repo = _FakeHomeRepository([
        StoreShelfPage(shelves: [_shelf('A')], nextOffset: 4, hasMore: true),
        StoreShelfPage(shelves: [_shelf('B')], nextOffset: 8, hasMore: true),
      ]);
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(storeShelvesProvider.future);
      final notifier = container.read(storeShelvesProvider.notifier);
      repo.failNext = true;
      await notifier.loadMore();
      expect(container.read(storeShelvesProvider).value!.moreFailed, isTrue);

      // Scrolling again doesn't hammer a failing server.
      await notifier.loadMore();
      expect(repo.offsets, [0, 4]);

      await notifier.retry();
      final state = container.read(storeShelvesProvider).value!;
      expect(state.moreFailed, isFalse);
      expect(state.shelves.map((s) => s.store.storeName), ['A', 'B']);
    });

    testWidgets('the section shows the loaded shelves and the loading row', (
      tester,
    ) async {
      final repo = _FakeHomeRepository([
        StoreShelfPage(
          shelves: [_shelf('Hobisaya'), _shelf('Menara TCG')],
          nextOffset: 4,
          hasMore: true,
        ),
      ]);
      await tester.pumpWidget(
        _app(
          const StoreShelvesSection(),
          overrides: [homeRepositoryProvider.overrideWithValue(repo)],
        ),
      );
      expect(find.text('Memuat toko lainnya...'), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('Listing baru dari toko'), findsOneWidget);
      expect(find.text('Hobisaya'), findsOneWidget);
      expect(find.text('Menara TCG'), findsOneWidget);
      expect(find.text('Memuat toko lainnya...'), findsNothing);
    });
  });

  test('catalogs: Indonesian first, then A–Z by label', () {
    const kr = CardLanguage(raw: 'kr', shortLabel: 'KR', labelId: 'Korea');
    final ordered = orderCatalogLanguages([
      CardLanguage.en,
      CardLanguage.jp,
      kr,
      CardLanguage.cn,
      CardLanguage.id,
    ]);
    expect(ordered.map((l) => l.shortLabel), ['ID', 'CN', 'EN', 'JP', 'KR']);
  });

  testWidgets('banners: one dot each, the current one drawn long', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const HomeBannerCarousel()));
    await tester.pumpAndSettle();

    final dots = find.byType(AnimatedContainer);
    expect(dots, findsNWidgets(homeBanners.length));
    expect(tester.getSize(dots.first).width, 18);
    expect(tester.getSize(dots.at(1)).width, 6);
    // The design's 340-wide banner on a 430-wide screen.
    expect(tester.getSize(find.byType(Image).first).width, closeTo(340, 0.5));

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(dots.first).width, 6);
    expect(tester.getSize(dots.at(1)).width, 18);
  });
}
