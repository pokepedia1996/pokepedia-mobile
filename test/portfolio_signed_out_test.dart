import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/portfolio_value_chart.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/portfolio_value_section.dart';

/// Signed out, the section shows the shape of the chart behind a blur with a
/// way in — rather than hiding it or, worse, showing figures that could be
/// mistaken for the reader's own.
/// Stands in for the real notifier, which would reach for Supabase.
class _SignedOutAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

Widget _host() {
  return ProviderScope(
    overrides: [authProvider.overrideWith(_SignedOutAuth.new)],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [PortfolioValueSection()],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('signed out: blurred preview with a sign-in call to action', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // The graph is still there — drawn, just unreadable.
    expect(find.byType(PortfolioSparkline), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);

    // And the way in is on top of it.
    expect(find.text('Lacak nilai koleksimu'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Masuk'), findsOneWidget);
  });

  testWidgets('the blurred layer cannot be interacted with', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // A ListView wraps its own content in IgnorePointer for overscroll, so
    // take the nearest ancestor — ours.
    final ignorePointer = tester.widget<IgnorePointer>(
      find
          .ancestor(
            of: find.byType(ImageFiltered),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(
      ignorePointer.ignoring,
      isTrue,
      reason:
          'the placeholder is not real data and must not be tappable, '
          'matching the web gate\'s pointer-events-none',
    );
  });

  testWidgets('the preview shows no rupiah figure to misread', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.textContaining('Rp'), findsNothing);
  });
}
