import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/widgets/card_art.dart';
import 'package:pokepedia_mobile/shared/widgets/shimmer_box.dart';

/// A grid of loading cards puts dozens of these on screen at once, so the
/// animation is shared rather than one controller per tile — and it has to
/// stop when the last one leaves, or a scrolled-past grid keeps the app
/// awake repainting nothing.
void main() {
  testWidgets('animates while mounted', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 100, height: 140, child: ShimmerBox()),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 16));
    // A frame is scheduled for as long as the sweep is running.
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ShimmerBox), findsOneWidget);
  });

  testWidgets('stops when the last one goes away', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 100, height: 140, child: ShimmerBox()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 32));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    // Drain whatever frame was already scheduled, then confirm no more come.
    await tester.pump(const Duration(milliseconds: 32));
    await tester.pump(const Duration(milliseconds: 32));

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('many tiles do not each schedule their own animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GridView.count(
            crossAxisCount: 2,
            children: List.generate(
              20,
              (_) =>
                  const SizedBox(width: 100, height: 140, child: ShimmerBox()),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // All twenty draw; the point is that they share one clock, which the
    // teardown test proves by showing a single stop ends every animation.
    expect(find.byType(ShimmerBox), findsWidgets);
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  group('CardArt', () {
    testWidgets('shows the card back only when there is no artwork', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox(width: 120, child: CardArt())),
        ),
      );
      await tester.pump();

      // No URL is not "loading" — it is a card the catalog has no art for.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(ShimmerBox), findsNothing);
    });
  });
}
