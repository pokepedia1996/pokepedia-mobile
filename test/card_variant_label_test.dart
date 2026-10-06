import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/widgets/card_grid_item.dart';

CardModel _card(String variant) => CardModel(
  id: 1,
  category: CardCategory.pokemon,
  nameId: 'Budew',
  expansionCode: 'SV8A',
  packSlug: 'sv8a',
  collectorNumber: '001/187',
  rarity: 'C',
  variant: variant,
);

/// Every finish of a print is its own catalog row with the same name,
/// number and art. Without the label a set's reverse and its plain print
/// are two identical tiles at different prices.
void main() {
  group('variantLabel', () {
    test('formats the way web\'s formatVariantLabel does', () {
      expect(_card('reverse').variantLabel, 'Holo Reverse');
      expect(_card('master ball').variantLabel, 'Holo Master Ball');
      expect(_card('POKE BALL').variantLabel, 'Holo Poke Ball');
    });

    test('says nothing for the plain print', () {
      // Web's VariantLabel returns null for "normal", whatever its case.
      expect(_card('normal').variantLabel, isNull);
      expect(_card('Normal').variantLabel, isNull);
      expect(_card('  ').variantLabel, isNull);
    });
  });

  testWidgets('the grid tile shows it under the name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final variant in ['normal', 'reverse'])
                SizedBox(
                  width: 200,
                  height: 400,
                  child: CardGridItem(card: _card(variant), onTap: () {}),
                ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Holo Reverse'), findsOneWidget);
    final label = tester.widget<Text>(find.text('Holo Reverse'));
    expect(label.style?.fontStyle, FontStyle.italic);
  });
}
