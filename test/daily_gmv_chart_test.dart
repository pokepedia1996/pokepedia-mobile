import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/daily_gmv_chart.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_dashboard.dart';

Widget _host(List<DailyGmv> data) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [DailyGmvChart(data: data)],
      ),
    ),
  );
}

void main() {
  testWidgets('renders inside a ListView', (tester) async {
    await tester.pumpWidget(
      _host([
        DailyGmv(day: '2026-08-18', gmv: 250000),
        DailyGmv(day: '2026-08-19', gmv: 0),
        DailyGmv(day: '2026-08-20', gmv: 1000000),
      ]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Tertinggi'), findsOneWidget);
  });

  testWidgets('shows an empty state rather than a zero-height chart', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Belum ada penjualan di periode ini.'), findsOneWidget);
  });

  testWidgets('tapping a bar reveals that day without resizing the card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        DailyGmv(day: '2026-08-19', gmv: 250000),
        DailyGmv(day: '2026-08-20', gmv: 1000000),
      ]),
    );
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byType(DailyGmvChart));

    // Tap the left half — the first day.
    final chart = tester.getRect(find.byType(DailyGmvChart));
    await tester.tapAt(
      Offset(chart.left + chart.width * 0.25, chart.center.dy),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('19 Agu'), findsOneWidget);
    expect(find.text('Rp250.000'), findsOneWidget);
    expect(tester.getSize(find.byType(DailyGmvChart)), before);
  });

  testWidgets('handles a series where nothing sold', (tester) async {
    await tester.pumpWidget(
      _host([
        DailyGmv(day: '2026-08-19', gmv: 0),
        DailyGmv(day: '2026-08-20', gmv: 0),
      ]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
