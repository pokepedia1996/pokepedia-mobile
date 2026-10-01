import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/models/card_market_price.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/widgets/card_grid_item.dart';
import 'package:pokepedia_mobile/shared/widgets/quantity_selector.dart';

const _card = CardModel(
  id: 1,
  category: CardCategory.pokemon,
  nameId: 'Alolan Exeggutor',
  expansionCode: 'MA6',
  packSlug: 'ma6',
  collectorNumber: '002/130',
  rarity: 'Rare',
  marketPrice: 2633,
  price7dAgo: 1000,
  priceSource: CardPriceSource.confirmed,
  owned: 3,
);

Future<void> _pump(WidgetTester tester, {Widget? footer}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 260,
            height: 560,
            child: CardGridItem(card: _card, onTap: () {}, footer: footer),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The price used to sit against the tile's right edge with the owned count
/// on the left. A column of prices that all start in the same place can be
/// compared down the grid without reading each one, so they lead the row now.
void main() {
  testWidgets('the price leads its row', (tester) async {
    await _pump(tester);

    final tile = tester.getRect(find.byType(CardGridItem));
    final price = tester.getRect(find.text('Rp2.633'));
    final qty = tester.getRect(find.text('Qty: 3'));

    expect(price.left, lessThan(qty.left));
    // Against the tile's own padding, not floating mid-row.
    expect(price.left - tile.left, lessThan(16));
  });

  testWidgets('a stepper takes the count off the price row', (tester) async {
    await _pump(
      tester,
      footer: Align(
        alignment: Alignment.centerRight,
        child: QuantitySelector(
          value: _card.owned,
          size: QuantitySelectorSize.sm,
          onChanged: (_) {},
        ),
      ),
    );

    // The stepper says how many; repeating it as text beside the price
    // would be the same number twice on one tile.
    expect(find.text('Qty: 3'), findsNothing);
    expect(find.byType(QuantitySelector), findsOneWidget);

    final tile = tester.getRect(find.byType(CardGridItem));
    final stepper = tester.getRect(find.byType(QuantitySelector));
    expect(tile.right - stepper.right, lessThan(16));
  });
}
