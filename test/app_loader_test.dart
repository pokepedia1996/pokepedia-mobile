import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/app_loader.dart';

void main() {
  testWidgets('the spinner says what it is doing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: AppLoader()),
      ),
    );
    expect(find.text('Memuat...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a caller can still name what is loading, or say nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              AppLoader(size: 96, label: 'Memuat listing...'),
              AppLoader(size: 96, label: null),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Memuat listing...'), findsOneWidget);
    expect(find.text('Memuat...'), findsNothing);
  });

  testWidgets('a 96pt loader with its caption fits the strip box', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Align(alignment: Alignment.topLeft, child: AppLoader(size: 96)),
        ),
      ),
    );
    // The root is a Center, which fills its parent — the Column inside is
    // the actual content box a fixed-height caller has to fit.
    final column = tester.getSize(
      find
          .descendant(of: find.byType(AppLoader), matching: find.byType(Column))
          .first,
    );
    // Recently-viewed pins its loader to a fixed box; if this grows past
    // that, the caption gets clipped there.
    expect(column.height, lessThanOrEqualTo(120));
  });
}
