import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/pikachu_loader.dart';

void main() {
  testWidgets('the running Pikachu says what it is doing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: PikachuLoader()),
      ),
    );
    // Web's gate captions its Pikachu "Memuat..."; every mobile loader used
    // to sit silent because the label defaulted to null.
    expect(find.text('Memuat...'), findsOneWidget);
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
              PikachuLoader(size: 96, label: 'Memuat listing...'),
              PikachuLoader(size: 96, label: null),
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
          body: Align(
            alignment: Alignment.topLeft,
            child: PikachuLoader(size: 96),
          ),
        ),
      ),
    );
    // The root is a Center, which fills its parent — the Column inside is
    // the actual content box a fixed-height caller has to fit.
    final column = tester.getSize(
      find
          .descendant(
            of: find.byType(PikachuLoader),
            matching: find.byType(Column),
          )
          .first,
    );
    // Recently-viewed pins its loader to a fixed box; if this grows past
    // that, the caption gets clipped there.
    expect(column.height, lessThanOrEqualTo(120));
  });
}
