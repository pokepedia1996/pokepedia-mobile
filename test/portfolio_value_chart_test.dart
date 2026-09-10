import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/portfolio_value_chart.dart';
import 'package:pokepedia_mobile/features/home/repository/models/portfolio_value.dart';
import 'package:pokepedia_mobile/features/home/usecase/portfolio_value_notifier.dart';

PortfolioValuePoint _point(String day, int value) =>
    PortfolioValuePoint(day: DateTime.parse(day), value: value);

const _holding = PortfolioHolding(
  cardId: 1,
  name: 'Pikachu',
  collectorNumber: '025/165',
  expansionCode: 'SV2a',
  rarity: 'Rare',
  packSlug: 'sv2a',
  quantity: 2,
  unitPrice: 50000,
);

Widget _host({
  required List<PortfolioValuePoint> series,
  List<PortfolioHolding> holdings = const [_holding],
}) {
  return ProviderScope(
    overrides: [
      portfolioHoldingsProvider.overrideWith((ref) async => holdings),
      portfolioValueSeriesProvider.overrideWith((ref) async => series),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [PortfolioValueChart()],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('draws the line when there is history', (tester) async {
    await tester.pumpWidget(
      _host(
        series: [
          _point('2026-08-18', 1000000),
          _point('2026-08-19', 1200000),
          _point('2026-08-20', 1150000),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Riwayat nilai belum tersedia'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('says history is missing rather than drawing a zero line', (
    tester,
  ) async {
    // Nothing at all to draw — no snapshots and no live value. Distinct
    // from one day, which is now drawn as a dot.
    await tester.pumpWidget(_host(series: const []));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Riwayat nilai belum tersedia'), findsOneWidget);
  });

  testWidgets('a single day is drawn, not withheld', (tester) async {
    // Today's value is computed live from the priced holdings, so it exists
    // as soon as a card is added — it does not wait for the nightly
    // snapshot. Showing "no history yet" for a number already printed above
    // the chart told the reader to come back tomorrow for something they
    // could already see.
    await tester.pumpWidget(_host(series: [_point('2026-08-20', 1000000)]));
    await tester.pumpAndSettle();

    expect(find.text('Riwayat nilai belum tersedia'), findsNothing);
    expect(find.byType(PortfolioSparkline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty portfolio says so instead', (tester) async {
    await tester.pumpWidget(_host(series: const [], holdings: const []));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada kartu di portofolio ini'), findsOneWidget);
  });

  testWidgets('a dead-flat series still renders', (tester) async {
    // Equal values would divide by a zero span if the painter did not guard
    // it.
    await tester.pumpWidget(
      _host(
        series: [_point('2026-08-19', 500000), _point('2026-08-20', 500000)],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('PortfolioRange', () {
    test('covers the sketched timeline filter, month by default', () {
      expect(PortfolioRange.values.map((r) => r.label), [
        '1H',
        '7H',
        '1B',
        '3B',
        '6B',
        'MAX',
      ]);
      expect(PortfolioRange.fallback, PortfolioRange.month);
      expect(PortfolioRange.month.days, 30);
      expect(PortfolioRange.max.days, isNull);
    });
  });

  group('PortfolioHolding', () {
    test('values a line by quantity', () {
      expect(_holding.value, 100000);
    });
  });
}
