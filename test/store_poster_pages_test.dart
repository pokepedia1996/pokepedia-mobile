import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/market/presentation/widgets/store_poster.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/models/listing_model.dart';

List<ListingModel> _listings(int count) => List.generate(
  count,
  (i) => ListingModel(
    id: i,
    sellerId: 'seller',
    slug: 'listing-$i',
    side: ListingSide.ask,
    price: 100000,
    condition: CardCondition.nm,
    quantity: 1,
    qtyLocked: 0,
    card: CardModel(
      id: i,
      category: CardCategory.pokemon,
      nameId: 'Charizard ex',
      expansionCode: 'SV2a',
      packSlug: 'sv2a',
      collectorNumber: '201/165',
      rarity: 'SAR',
    ),
    storeSlug: 'toko',
    storeName: 'Toko',
    isVerified: false,
    cityName: 'Jakarta',
    createdAt: DateTime(2026, 8, 1),
    status: ListingStatus.open,
  ),
);

void main() {
  final capacity = StorePoster.capacity;

  group('paginateForPoster', () {
    test('a store that fits on one poster gets one page', () {
      expect(paginateForPoster(_listings(capacity)), hasLength(1));
      expect(paginateForPoster(_listings(1)), hasLength(1));
    });

    test('no listings means no pages, not an empty poster', () {
      // The picker is hidden in this state; returning a blank page would
      // hand the share sheet an image of nothing.
      expect(paginateForPoster(const []), isEmpty);
    });

    test('page one is a card short, to make room for the "+N" tile', () {
      // The tile displaces a card. Paginating page one as a full twelve
      // would leave that card on no poster at all.
      // 27 listings: 11 on page one, then full pages, then the tail.
      final pages = paginateForPoster(_listings(capacity * 2 + 3));
      expect(pages.map((p) => p.length), [capacity - 1, capacity, 4]);
    });

    test('one card over the limit still splits into two pages', () {
      final pages = paginateForPoster(_listings(capacity + 1));
      expect(pages.map((p) => p.length), [capacity - 1, 2]);
    });

    test('every listing lands on exactly one page, in order', () {
      // The property the short first page exists to preserve.
      final all = _listings(capacity * 3 + 5);
      final flat = paginateForPoster(all).expand((p) => p).toList();
      expect(flat.map((l) => l.id), all.map((l) => l.id));
    });

    test('stops at the page cap however many listings there are', () {
      // Left uncapped this would silently attach hundreds of images to a
      // share intent, which most targets simply drop.
      final pages = paginateForPoster(_listings(capacity * 40));
      expect(pages, hasLength(maxPosterPages));
    });
  });

  group('posterPageTotal', () {
    test('page one reports the whole store', () {
      // It is the poster the sheet selects by default and the one that gets
      // posted alone, so its last tile has to say how much more there is.
      final pages = paginateForPoster(_listings(30));
      expect(posterPageTotal(pages, 0, 30), 30);
      // 11 cards drawn, so the tile reads "+19".
      expect(posterPageTotal(pages, 0, 30) - (capacity - 1), 19);
    });

    test('a store that fits on one poster advertises no remainder', () {
      final pages = paginateForPoster(_listings(capacity));
      expect(posterPageTotal(pages, 0, capacity), capacity);
    });

    test('a middle page counts only itself', () {
      // Repeating the remainder here would tell a reader who has all the
      // images that they are still missing most of them.
      final pages = paginateForPoster(_listings(capacity * 3));
      expect(posterPageTotal(pages, 1, capacity * 3), capacity);
    });

    test('a final page that exhausts the store shows no "+N" either', () {
      final total = capacity * 2 + 4;
      final pages = paginateForPoster(_listings(total));
      expect(posterPageTotal(pages, 2, total), pages.last.length);
    });

    test('the final page carries whatever the cap left behind', () {
      // Ten pages hold 11 + 9x12 = 119 cards; the rest never got a poster.
      final total = 200;
      final pages = paginateForPoster(_listings(total));
      final last = pages.length - 1;
      final shown = pages.fold<int>(0, (sum, page) => sum + page.length);

      expect(shown, capacity - 1 + capacity * (maxPosterPages - 1));
      expect(posterPageTotal(pages, last, total), capacity + (total - shown));
    });
  });

  group('condition abbreviations on tiles', () {
    test('reads as a short code, not a sentence', () {
      // Poster tiles are ~245px wide; the full label wraps and collides
      // with the price scrim.
      expect(CardCondition.nm.short, 'NM');
      expect(CardCondition.nm.short.length, lessThanOrEqualTo(6));
    });
  });
}
