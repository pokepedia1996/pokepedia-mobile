import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/deck_card_entry.dart';
import 'package:pokepedia_mobile/features/portfolio/utils/deck_pricing.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_market_price.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

DeckCardEntry _entry(int id, int quantity, {int? price}) {
  var card = CardModel.fromRow({
    'id': id,
    'category': 'Pokemon',
    'name_id': 'Kartu $id',
    'expansion_code': 'SV1',
    'collector_number': '$id',
  });
  if (price != null) {
    card = card.copyWith(
      price: CardMarketPrice(
        price: price,
        condition: CardCondition.nm,
        source: CardPriceSource.confirmed,
      ),
    );
  }
  return DeckCardEntry(
    card: card,
    quantity: quantity,
    category: DeckCategory.pokemon,
  );
}

/// Rp formatting without pinning the grouping character.
String _digits(String label) => label.replaceAll(RegExp(r'\D'), '');

void main() {
  test('total is price × quantity over priced rows', () {
    final summary = summarizeDeckPrice([
      _entry(1, 4, price: 10000),
      _entry(2, 2, price: 2500),
    ]);
    expect(summary.total, 45000);
    expect(summary.unpricedCount, 0);
    expect(summary.caption, 'Total harga');
    expect(_digits(summary.totalLabel), '45000');
  });

  test('unpriced rows are counted per row, not per copy', () {
    final summary = summarizeDeckPrice([
      _entry(1, 4, price: 10000),
      _entry(2, 3),
      _entry(3, 1),
    ]);
    expect(summary.total, 40000);
    expect(summary.unpricedCount, 2);
    expect(summary.hasAnyPrice, isTrue);
    expect(summary.caption, 'Total harga (2 kartu tanpa harga)');
  });

  test('a deck with no prices at all reads Rp- and no count', () {
    final summary = summarizeDeckPrice([_entry(1, 4), _entry(2, 1)]);
    expect(summary.hasAnyPrice, isFalse);
    expect(summary.totalLabel, 'Rp-');
    expect(summary.caption, 'Total harga');
  });

  test('row label multiplies by the copies held', () {
    expect(_digits(deckRowPriceLabel(_entry(1, 3, price: 1500))), '4500');
    expect(deckRowPriceLabel(_entry(1, 3)), 'Rp-');
  });

  test('search label is one copy', () {
    expect(
      _digits(deckSearchPriceLabel(_entry(1, 3, price: 1500).card)),
      '1500',
    );
  });
}
