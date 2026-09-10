import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/quantity_selector.dart';

Widget _harness({
  required int value,
  int min = 0,
  int max = 99,
  QuantitySelectorSize size = QuantitySelectorSize.md,
  ValueChanged<int>? onChanged,
}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Center(
      child: QuantitySelector(
        value: value,
        min: min,
        max: max,
        size: size,
        onChanged: onChanged ?? (_) {},
      ),
    ),
  ),
);

Size _boxOf(WidgetTester tester, Finder finder) => tester.getSize(finder.first);

/// The control is three separate boxes now — muted steppers either side of
/// the count on the card's own fill — matching `quantity-selector.tsx`.
void main() {
  testWidgets('lays out as stepper, count, stepper', (tester) async {
    await tester.pumpWidget(_harness(value: 3));

    expect(find.text('3'), findsOneWidget);
    // Web's md: h-8 buttons with an h-8 w-12 count between them.
    final containers = find.descendant(
      of: find.byType(QuantitySelector),
      matching: find.byType(Container),
    );
    expect(containers, findsNWidgets(3));
    expect(_boxOf(tester, containers.at(0)), const Size(32, 32));
    expect(_boxOf(tester, containers.at(1)), const Size(48, 32));
    expect(_boxOf(tester, containers.at(2)), const Size(32, 32));
  });

  testWidgets('the small size is the dense-row variant', (tester) async {
    await tester.pumpWidget(_harness(value: 1, size: QuantitySelectorSize.sm));
    final containers = find.descendant(
      of: find.byType(QuantitySelector),
      matching: find.byType(Container),
    );
    expect(_boxOf(tester, containers.at(0)), const Size(24, 24));
    expect(_boxOf(tester, containers.at(1)), const Size(32, 24));
  });

  testWidgets('steps within its bounds', (tester) async {
    var current = 1;
    await tester.pumpWidget(
      _harness(value: current, onChanged: (v) => current = v),
    );

    // Plus is last in the row, minus first.
    await tester.tap(find.byType(InkWell).last);
    expect(current, 2);

    await tester.tap(find.byType(InkWell).first);
    expect(current, 0);
  });

  testWidgets('a reached bound stops responding but stays visible', (
    tester,
  ) async {
    var changes = 0;
    await tester.pumpWidget(
      _harness(value: 0, min: 0, max: 5, onChanged: (_) => changes++),
    );

    // At the minimum: minus is inert, and still drawn — the control keeps
    // its shape rather than shifting as it hits a bound.
    await tester.tap(find.byType(InkWell).first);
    expect(changes, 0);
    expect(find.byType(Opacity), findsNWidgets(2));

    await tester.tap(find.byType(InkWell).last);
    expect(changes, 1);
  });
}
