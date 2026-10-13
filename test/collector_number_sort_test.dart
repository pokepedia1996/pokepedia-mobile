import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/card_filtering.dart';

/// MA6 numbers its RGB Mews R/RGB, G/RGB, B/RGB and its basic energies with
/// letters (DAR, FIG). A plain natural sort put every lettered number after
/// the numbered cards alphabetically, so the Mews were split up among the
/// energies. They now follow the numbered cards in R-G-B order, energies
/// last, as web's `compareCollectorNumber` orders them.
CardModel _card(int id, String number) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: 'Kartu $number',
  expansionCode: 'MA6',
  packSlug: 'ma6',
  collectorNumber: number,
  rarity: 'C',
  variant: 'normal',
);

List<String> _order(List<CardModel> cards, CardSortOption sort) => [
  for (final c in sortCards(cards, sort)) c.collectorNumber,
];

void main() {
  final cards = [
    _card(1, 'FIG'),
    _card(2, 'B/RGB'),
    _card(3, '196/130'),
    _card(4, 'DAR'),
    _card(5, 'R/RGB'),
    _card(6, '020/130'),
    _card(7, 'G/RGB'),
    _card(8, '001/130'),
  ];

  const ascending = [
    '001/130',
    '020/130',
    '196/130',
    'R/RGB',
    'G/RGB',
    'B/RGB',
    'DAR',
    'FIG',
  ];

  test('numbered cards, then the RGB Mews, then the energies', () {
    expect(_order(cards, CardSortOption.numberAsc), ascending);
  });

  test('descending turns the whole order round, as web does', () {
    expect(
      _order(cards, CardSortOption.numberDesc),
      ascending.reversed.toList(),
    );
  });
}
