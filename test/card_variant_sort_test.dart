import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/card_filtering.dart';

/// An expansion's default "Nomor ↑" sort compared collector numbers alone,
/// so the prints sharing a number — normal, Poké Ball, Master Ball — came
/// out in whatever order the server sent them. They now sit under their
/// number base print first, as web and `_card_holo_rank` order them.
CardModel _card(int id, String number, String variant) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: 'Kartu $number',
  expansionCode: 'MA6',
  packSlug: 'ma6',
  collectorNumber: number,
  rarity: 'C',
  variant: variant,
);

List<String> _order(List<CardModel> cards, CardSortOption sort) => [
  for (final c in sortCards(cards, sort)) '${c.collectorNumber} ${c.variant}',
];

void main() {
  // Shuffled the way the server can hand them over.
  final cards = [
    _card(1, '002/130', 'Masterball'),
    _card(2, '001/130', 'Masterball'),
    _card(3, '002/130', 'normal'),
    _card(4, '001/130', 'Pokeball'),
    _card(5, '001/130', 'normal'),
    _card(6, '002/130', 'Pokeball'),
  ];

  test('by number, each print normal → Poké Ball → Master Ball', () {
    expect(_order(cards, CardSortOption.numberAsc), [
      '001/130 normal',
      '001/130 Pokeball',
      '001/130 Masterball',
      '002/130 normal',
      '002/130 Pokeball',
      '002/130 Masterball',
    ]);
  });

  test('descending turns both round, as web does', () {
    expect(
      _order(cards, CardSortOption.numberDesc).first,
      '002/130 Masterball',
    );
    expect(_order(cards, CardSortOption.numberDesc).last, '001/130 normal');
  });

  test('both spellings of Master Ball sit between Poké Ball and Reverse', () {
    for (final master in ['Masterball', 'Master Ball']) {
      expect(compareVariant('Pokeball', master), lessThan(0));
      expect(compareVariant(master, 'Reverse'), lessThan(0));
    }
  });

  test('an unknown finish goes after every known one', () {
    expect(compareVariant('Reverse', 'Something New'), lessThan(0));
    expect(compareVariant('normal', 'Something New'), lessThan(0));
  });
}
