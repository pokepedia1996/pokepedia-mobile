import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/models/card_market_price.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/widgets/card_grid_item.dart';
import 'package:pokepedia_mobile/shared/widgets/quantity_selector.dart';

/// `cardGridDelegate` sizes its cells from one measured constant. If the
/// tile grows a row and nobody updates it, every catalog grid overflows —
/// this is what makes that a failing build instead.
///
/// Only wide cells are checked, for the same reason as
/// `listing_card_height_test`: `flutter_test` draws text in a fallback font
/// whose glyphs are square, so strings measure far wider here than on a
/// device and a narrow cell overflows horizontally, which swamps the
/// vertical measurement this is actually about. Nothing is lost by it —
/// every row of the tile is one line of a fixed size, so what the chrome
/// has to cover doesn't change with the cell's width.
const _card = CardModel(
  id: 1,
  category: CardCategory.pokemon,
  nameId: 'Professor Elm Training Method',
  expansionCode: 'SV2a',
  packSlug: 'sv2a',
  collectorNumber: '038/165',
  rarity: 'Rare',
  // A four-figure price, not a seven-figure one: the harness's square
  // fallback font measures a long price wide enough to overflow the tile
  // horizontally, which reports as an error and masks the vertical fit this
  // is measuring.
  marketPrice: 20000,
  // Priced off confirmed sales with a week to compare against, so the tile
  // draws its trend too — the widest the price row ever gets.
  price7dAgo: 10000,
  priceSource: CardPriceSource.confirmed,
  owned: 3,
  // A finish, so the italic variant line is drawn: the tallest a tile gets,
  // which is the one the chrome has to cover.
  variant: 'reverse',
);

Future<bool> _overflows(
  WidgetTester tester,
  double width,
  double height, {
  Widget? footer,
  bool? selected,
  CardModel card = _card,
}) async {
  // A blank frame first: pumping the identical tree twice repaints nothing,
  // so no fresh overflow error is reported and every size after the first
  // looks fine.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.takeException();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: CardGridItem(
              card: card,
              onTap: () {},
              footer: footer,
              selected: selected,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.takeException() != null;
}

/// What a grid row gives a cell this wide.
double _extentFor(
  double cellWidth, {
  double extraChrome = 0,
  bool hasVariant = true,
}) => cardGridRowExtent(
  cellWidth,
  hasVariant: hasVariant,
  extraChrome: extraChrome,
);

/// The same card as a plain print: no variant line, and a row of these is
/// given no room for one.
final _plain = CardModel(
  id: _card.id,
  category: _card.category,
  nameId: _card.nameId,
  expansionCode: _card.expansionCode,
  packSlug: _card.packSlug,
  collectorNumber: _card.collectorNumber,
  rarity: _card.rarity,
  marketPrice: _card.marketPrice,
  price7dAgo: _card.price7dAgo,
  priceSource: _card.priceSource,
  owned: _card.owned,
);

void main() {
  testWidgets('the harness can see an overflow at all', (tester) async {
    // Without this the numbers below would be meaningless: a harness that
    // never reports overflow reports every height as fine.
    expect(
      await _overflows(tester, 173, 60),
      isTrue,
      reason: '60pt must overflow — the artwork alone is taller',
    );
  });

  testWidgets('the computed cell fits a tile', (tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (final cell in [260.0, 320.0]) {
      final extent = _extentFor(cell);
      expect(
        await _overflows(tester, cell, extent),
        isFalse,
        reason: 'cell ${cell}x$extent overflows',
      );
    }
  });

  testWidgets('a row of plain prints fits without the variant line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (final cell in [260.0, 320.0]) {
      final extent = _extentFor(cell, hasVariant: false);
      expect(
        await _overflows(tester, cell, extent, card: _plain),
        isFalse,
        reason: 'plain cell ${cell}x$extent overflows',
      );
    }
  });

  testWidgets('a row without variants is shorter by exactly that line', (
    tester,
  ) async {
    expect(
      _extentFor(260) - _extentFor(260, hasVariant: false),
      cardGridVariantChrome,
    );
  });

  testWidgets('an edit-mode tile fits its footer chrome', (tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (final cell in [260.0, 320.0]) {
      final extent = _extentFor(cell, extraChrome: cardGridItemFooterChrome);
      expect(
        await _overflows(
          tester,
          cell,
          extent,
          selected: true,
          footer: const QuantitySelector(
            value: 3,
            onChanged: _ignore,
            size: QuantitySelectorSize.sm,
          ),
        ),
        isFalse,
        reason: 'editing cell ${cell}x$extent overflows',
      );
    }
  });
}

void _ignore(int _) {}
