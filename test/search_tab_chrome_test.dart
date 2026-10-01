import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/search/presentation/advanced_search_page.dart';
import 'package:pokepedia_mobile/shared/widgets/app_search_field.dart';
import 'package:pokepedia_mobile/shared/widgets/app_top_bar.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 1000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: AdvancedSearchPage())),
  );
  await tester.pump();
}

/// The tab people search from built its own `TextField` on the card fill,
/// taller than the pill every other screen uses — so the one box that had to
/// look familiar was the one that did not.
void main() {
  testWidgets('the search box is the app\'s own field', (tester) async {
    await _pump(tester);

    final fields = find.descendant(
      of: find.byType(AppTopBar),
      matching: find.byType(AppSearchField),
    );
    expect(fields, findsOneWidget);

    // 40pt, the height `AppSearchField` gives every other search box.
    expect(tester.getSize(fields).height, 40);
  });

  testWidgets('the filter panel is animated in, not swapped', (tester) async {
    await _pump(tester);

    await tester.tap(find.bySemanticsLabel('Buka filter pencarian'));
    await tester.pump();
    // One frame in, the panel exists but has not finished arriving — which
    // is the difference between an animation and a replacement.
    await tester.pump(const Duration(milliseconds: 60));

    final fade = tester.widgetList<FadeTransition>(find.byType(FadeTransition));
    expect(
      fade.any((f) => f.opacity.value > 0 && f.opacity.value < 1),
      isTrue,
      reason: 'something should be mid-fade',
    );

    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Tutup filter pencarian'), findsOneWidget);
  });
}
