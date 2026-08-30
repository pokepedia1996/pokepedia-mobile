import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/app_top_bar.dart';

/// The bar is two rows that become one on scroll, so what matters is that
/// the logo row actually gives its height back — a row that only fades still
/// pushes the page down by 40px.
Future<ProviderContainer> _host(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        // The cart reads the live cart provider, which would reach Supabase.
        home: const Scaffold(body: AppTopBar(showCart: false)),
      ),
    ),
  );
  return container;
}

/// The clip around the logo row is the first one in the bar.
double _logoRowHeight(WidgetTester tester) =>
    tester.getSize(find.byType(ClipRect).first).height;

void main() {
  testWidgets('opens as two rows: logo above the search field', (tester) async {
    await _host(tester);
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Cari kartu...'), findsOneWidget);
    expect(_logoRowHeight(tester), 40);

    // Two rows, so the search field sits below the logo.
    final logo = tester.getRect(find.byType(Image));
    final search = tester.getRect(find.text('Cari kartu...'));
    expect(search.top, greaterThan(logo.bottom));
  });

  testWidgets('scrolling folds the logo row away', (tester) async {
    final container = await _host(tester);
    await tester.pumpAndSettle();

    container.read(topBarScrolledProvider.notifier).state = true;
    await tester.pumpAndSettle();

    expect(_logoRowHeight(tester), 0);
    // The search field stays — it's the row that survives.
    expect(find.text('Cari kartu...'), findsOneWidget);
  });

  testWidgets('scrolling back to the top brings the logo back', (tester) async {
    final container = await _host(tester);
    container.read(topBarScrolledProvider.notifier).state = true;
    await tester.pumpAndSettle();

    container.read(topBarScrolledProvider.notifier).state = false;
    await tester.pumpAndSettle();

    expect(_logoRowHeight(tester), 40);
  });

  testWidgets('the bar is shorter once collapsed', (tester) async {
    final container = await _host(tester);
    await tester.pumpAndSettle();
    final expanded = tester.getSize(find.byType(AppTopBar)).height;

    container.read(topBarScrolledProvider.notifier).state = true;
    await tester.pumpAndSettle();
    final collapsed = tester.getSize(find.byType(AppTopBar)).height;

    // The row itself plus the 8px gap that closes with it.
    expect(collapsed, expanded - 48);
  });
}
