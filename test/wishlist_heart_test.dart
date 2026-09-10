import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/widgets/wishlist_heart.dart';

/// Every wishlist control used to draw the same hollow heart in both states
/// and lean entirely on colour — `wishlisted ? heart : heart` was in four
/// files. Colour alone reads as a highlight, not as "this is on my list".
void main() {
  Future<void> pump(WidgetTester tester, bool active) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: WishlistHeart(active: active))),
    ),
  );

  testWidgets('on the list, the heart is solid', (tester) async {
    await pump(tester, true);

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets('off the list, it is an outline', (tester) async {
    await pump(tester, false);

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('the two states are the same size', (tester) async {
    await pump(tester, true);
    final on = tester.getSize(find.byType(WishlistHeart));
    await pump(tester, false);
    final off = tester.getSize(find.byType(WishlistHeart));

    // A toggle that resizes as it flips makes the row jump.
    expect(on, off);
  });
}
