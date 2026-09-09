import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/expansions_page.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/shared/models/pack_model.dart';

PackModel _pack(int i) => PackModel(
  slug: 'pack-$i',
  name: 'Ekspansi $i',
  mark: 'EX$i',
  series: 'Matahari & Bulan',
  releaseDate: '2026-01-${i.toString().padLeft(2, '0')}',
  cardCount: 100,
);

SeriesGroup _group(int packs) => SeriesGroup(
  series: 'Matahari & Bulan',
  packs: [for (var i = 1; i <= packs; i++) _pack(i)],
);

Future<void> _pump(WidgetTester tester, int packCount) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        seriesGroupsProvider.overrideWith((ref) async => [_group(packCount)]),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ExpansionsPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('a long series shows six and offers the rest', (tester) async {
    // Wide, and at dpr 1: `flutter_test`'s fallback font measures far larger
    // than a real one, and a phone-width grid overflows PackCard's column
    // before any of this test's assertions get a chance to run.
    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, 14);

    // Counted rather than named: the page sorts newest-first, so *which*
    // six show depends on the sort, but how many is the behaviour here.
    expect(find.textContaining('Ekspansi '), findsNWidgets(6));
    // The count rides on the button — "Lihat semua" alone doesn't say
    // whether it hides two expansions or twenty.
    expect(find.text('Lihat semua (8 lagi)'), findsOneWidget);
  });

  testWidgets('tapping it reveals the rest, and folds back', (tester) async {
    tester.view.physicalSize = const Size(1400, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, 14);
    await tester.tap(find.text('Lihat semua (8 lagi)'));
    await tester.pump();

    expect(find.textContaining('Ekspansi '), findsNWidgets(14));
    expect(find.text('Tampilkan lebih sedikit'), findsOneWidget);

    // And it folds back.
    await tester.tap(find.text('Tampilkan lebih sedikit'));
    await tester.pump();
    expect(find.textContaining('Ekspansi '), findsNWidgets(6));
  });

  testWidgets('a short series gets no CTA at all', (tester) async {
    // Wide, and at dpr 1: `flutter_test`'s fallback font measures far larger
    // than a real one, and a phone-width grid overflows PackCard's column
    // before any of this test's assertions get a chance to run.
    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, 4);

    expect(find.textContaining('Ekspansi '), findsNWidgets(4));
    expect(find.textContaining('Lihat semua'), findsNothing);
  });
}
