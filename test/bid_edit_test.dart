import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/proposals/presentation/widgets/bid_edit_sheet.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/my_bid.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

MyBidModel _bid({int price = 100000, int quantity = 3, int qtyLocked = 0}) =>
    MyBidModel(
      slug: 'bid-1',
      card: CardModel(
        id: 7,
        category: CardCategory.pokemon,
        nameId: 'Charizard ex',
        expansionCode: 'SV2a',
        packSlug: 'sv2a',
        collectorNumber: '201/165',
        rarity: 'SAR',
      ),
      price: price,
      condition: CardCondition.nm,
      quantity: quantity,
      qtyLocked: qtyLocked,
    );

Future<BidEdit?> _openAndSubmit(
  WidgetTester tester,
  MyBidModel bid, {
  String? typePrice,
  int quantityTaps = 0,
  bool decrement = false,
}) async {
  BidEdit? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await showBidEditSheet(context, bid: bid);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  if (typePrice != null) {
    await tester.enterText(find.byType(TextField), typePrice);
    await tester.pump();
  }
  for (var i = 0; i < quantityTaps; i++) {
    await tester.tap(
      find.byIcon(
        decrement ? Icons.remove_circle_outline : Icons.add_circle_outline,
      ),
    );
    await tester.pump();
  }

  await tester.tap(find.text('Simpan'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('sends only the fields that changed', (tester) async {
    // `update_order_self` treats null as "leave it", so an unchanged field
    // must not be sent — otherwise every edit rewrites both columns.
    final edit = await _openAndSubmit(
      tester,
      _bid(price: 100000, quantity: 3),
      typePrice: '125000',
    );

    expect(edit, isNotNull);
    expect(edit!.price, 125000);
    expect(edit.quantity, isNull);
  });

  testWidgets('a quantity-only change leaves price null', (tester) async {
    final edit = await _openAndSubmit(
      tester,
      _bid(quantity: 3),
      quantityTaps: 1,
    );

    expect(edit!.price, isNull);
    expect(edit.quantity, 4);
  });

  testWidgets('submitting with nothing changed returns null', (tester) async {
    // The RPC answers `nothing_to_update`; better to close quietly than to
    // spend a round trip on it.
    final edit = await _openAndSubmit(tester, _bid());
    expect(edit, isNull);
  });

  testWidgets('an invalid price is refused before it reaches the server', (
    tester,
  ) async {
    final edit = await _openAndSubmit(tester, _bid(), typePrice: '0');
    expect(edit, isNull);
    expect(find.text('Harga tidak valid.'), findsOneWidget);
  });

  testWidgets('quantity cannot go below what a buyer has locked', (
    tester,
  ) async {
    // `quantity_below_locked` is the server's guard; the stepper stops at
    // the same floor rather than offering a value that will bounce.
    await _openAndSubmit(
      tester,
      _bid(quantity: 2, qtyLocked: 2),
      quantityTaps: 3,
      decrement: true,
    );
    // Stayed at the locked floor, so nothing changed and the sheet closed
    // without an edit.
    expect(find.text('2'), findsNothing);
  });

  testWidgets('quantity stops at the server cap of 99', (tester) async {
    final edit = await _openAndSubmit(
      tester,
      _bid(quantity: 98),
      quantityTaps: 5,
    );
    expect(edit!.quantity, 99);
  });
}
