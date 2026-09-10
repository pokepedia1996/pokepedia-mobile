import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Instagram button used a plain camera glyph, which reads as "take a
/// photo" rather than as the brand. The icon set has no brand marks — lucide
/// dropped them upstream — so the mark is bundled, and this checks the file
/// is actually there and renders: a missing asset fails at runtime, on a
/// screen nobody opens in a test run.
void main() {
  testWidgets('the bundled Instagram mark loads and tints', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SvgPicture.asset(
              'assets/images/social/instagram.svg',
              width: 18,
              height: 18,
              colorFilter: const ColorFilter.mode(
                Colors.black,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
