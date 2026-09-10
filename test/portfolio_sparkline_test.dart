import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/portfolio_value_chart.dart';
import 'package:pokepedia_mobile/features/home/repository/models/portfolio_value.dart';

Future<void> _pump(WidgetTester tester, List<PortfolioValuePoint> series) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 80,
          child: PortfolioSparkline(series: series),
        ),
      ),
    ),
  );
}

PortfolioValuePoint _p(int day, int value) =>
    PortfolioValuePoint(day: DateTime.utc(2026, 9, day), value: value);

void main() {
  testWidgets('a single day paints something rather than nothing', (
    tester,
  ) async {
    // Today's value is computed live, so it exists the moment a priced card
    // is added. Showing a blank chart — or worse, "come back tomorrow" — for
    // a number already printed above the chart is not acceptable.
    await _pump(tester, [_p(7, 250000)]);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('an empty series paints nothing and does not throw', (
    tester,
  ) async {
    await _pump(tester, const []);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('two or more days still draw the line', (tester) async {
    await _pump(tester, [_p(5, 100000), _p(6, 120000), _p(7, 90000)]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('one day rises from the floor to the value, filled beneath', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 200,
                height: 100,
                child: PortfolioSparkline(series: [_p(7, 250000)]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    late ByteData pixels;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      pixels = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
    });

    final width = 200, height = 100;
    int alphaAt(int x, int y) => pixels.getUint8((y * width + x) * 4 + 3);

    // The reading rises from the chart floor on the left to the value on the
    // right, so the shape itself carries the change.
    expect(
      alphaAt(2, height - 2),
      greaterThan(0),
      reason: 'starts at the floor on the left',
    );
    expect(
      alphaAt(width - 2, 4),
      greaterThan(0),
      reason: 'reaches the value at the top right',
    );

    // Under the rise is tinted...
    expect(
      alphaAt(width - 10, height - 10),
      greaterThan(0),
      reason: 'area under the rise should be tinted',
    );
    // ...and above it is clear, so the fill follows the line rather than
    // washing the whole box.
    expect(
      alphaAt(8, 4),
      0,
      reason: 'above the rise, at the left, stays empty',
    );
  });
}
