import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/card_filtering.dart';

/// Sorting on the results page is the server's — these values go straight to
/// `search_cards_fuzzy` as `p_sort`, which web's route allowlists one at a
/// time, so a label change that forgets the wire value silently falls back to
/// relevance order. The facets beside them are applied on the client, over
/// the rows already fetched, the way the expansion detail page filters.
void main() {
  group('sort values', () {
    test('match web CARD_SORT_OPTIONS', () {
      expect(CardSortOption.setDesc.raw, 'set-desc');
      expect(CardSortOption.setAsc.raw, 'set-asc');
      expect(CardSortOption.numberAsc.raw, 'number-asc');
      expect(CardSortOption.nameDesc.raw, 'name-desc');
      expect(CardSortOption.rarityAsc.raw, 'rarity-asc');
      expect(CardSortOption.priceDesc.raw, 'price-desc');
    });

    test('newest first is what the bar opens on, and it is labelled', () {
      expect(CardSortOption.setDesc.label, 'Terbaru');
      expect(CardSortOption.setAsc.label, 'Terlama');
    });

    test('every option carries a distinct wire value', () {
      final raws = CardSortOption.values.map((o) => o.raw).toSet();
      expect(raws, hasLength(CardSortOption.values.length));
    });
  });

  group('within-pack options', () {
    test('drop the two that order by expansion', () {
      // A pack is one expansion; sorting it by expansion says nothing, which
      // is why web builds PACK_DETAIL_SORT_OPTIONS by filtering those out.
      expect(
        cardSortOptionsWithinPack,
        isNot(contains(CardSortOption.setDesc)),
      );
      expect(cardSortOptionsWithinPack, isNot(contains(CardSortOption.setAsc)));
      expect(cardSortOptionsWithinPack, hasLength(8));
    });

    test('keep everything else in the full list', () {
      final rest = CardSortOption.values
          .where(
            (o) => o != CardSortOption.setDesc && o != CardSortOption.setAsc,
          )
          .toList();
      expect(cardSortOptionsWithinPack, rest);
    });
  });

  group('facets over the fetched rows', () {
    CardModel card({
      required int id,
      CardCategory category = CardCategory.pokemon,
      String rarity = 'C',
      int owned = 0,
    }) => CardModel(
      id: id,
      category: category,
      nameId: 'Card $id',
      expansionCode: 'SV1',
      packSlug: 'sv1',
      collectorNumber: '00$id',
      rarity: rarity,
      owned: owned,
    );

    test('narrow the list the same way the expansion page does', () {
      final cards = [
        card(id: 1, rarity: 'SAR'),
        card(id: 2, rarity: 'C'),
        card(id: 3, category: CardCategory.trainer, rarity: 'SAR'),
      ];

      final bySAR = applyCardFilters(
        cards,
        const CardFilters(rarities: {'SAR'}),
      );
      expect(bySAR.map((c) => c.id), [1, 3]);

      final byCategory = applyCardFilters(
        cards,
        const CardFilters(categories: {CardCategory.pokemon}),
      );
      expect(byCategory.map((c) => c.id), [1, 2]);
    });

    test('offer only values the fetched rows actually carry', () {
      // Options come from the rows on screen, so a rarity nothing matched is
      // never offered — which is the point of deriving them.
      final options = deriveCardFilterOptions([
        card(id: 1, rarity: 'SAR'),
        card(id: 2, rarity: 'SAR'),
      ]);
      expect(options.rarities, ['SAR']);
      expect(options.categories, [CardCategory.pokemon]);
    });
  });

  group('client-side fallback', () {
    CardModel card(String expansion, String number) => CardModel(
      id: number.hashCode,
      category: CardCategory.pokemon,
      nameId: 'Card $number',
      expansionCode: expansion,
      packSlug: expansion.toLowerCase(),
      collectorNumber: number,
      rarity: 'C',
    );

    test('orders by expansion when the server has not', () {
      final cards = [
        card('SV1', '001'),
        card('SV9', '002'),
        card('SV5', '003'),
      ];
      expect(
        sortCards(cards, CardSortOption.setDesc).map((c) => c.expansionCode),
        ['SV9', 'SV5', 'SV1'],
      );
      expect(
        sortCards(cards, CardSortOption.setAsc).map((c) => c.expansionCode),
        ['SV1', 'SV5', 'SV9'],
      );
    });
  });
}
