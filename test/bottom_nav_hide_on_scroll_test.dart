import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/app_bottom_nav.dart';

Future<void> _pump(WidgetTester tester, {required bool hidden}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        extendBody: true,
        body: const SizedBox.expand(),
        bottomNavigationBar: AppBottomNav(
          currentIndex: 0,
          hidden: hidden,
          onTap: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The pill used to shrink while the page scrolled down, which left it over
/// the last row of whatever was being read. Reading a grid of listings is
/// most of what this app is for, so it leaves instead.
void main() {
  testWidgets('the pill sits on screen when nothing has scrolled', (
    tester,
  ) async {
    await _pump(tester, hidden: false);

    final screen = tester.getSize(find.byType(MaterialApp)).height;
    expect(tester.getRect(find.text('Beranda')).bottom, lessThan(screen));
  });

  testWidgets('it leaves the screen entirely when hidden', (tester) async {
    await _pump(tester, hidden: true);

    // Off the bottom, not merely smaller: a shrunk pill still covers what it
    // was covering.
    final screen = tester.getSize(find.byType(MaterialApp)).height;
    expect(
      tester.getRect(find.text('Beranda')).top,
      greaterThanOrEqualTo(screen),
    );
  });

  testWidgets('a hidden pill cannot be tapped through', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: AppBottomNav(
            currentIndex: 0,
            hidden: true,
            onTap: (_) => taps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Beranda'), warnIfMissed: false);
    await tester.pump();

    expect(taps, 0);
  });
}
