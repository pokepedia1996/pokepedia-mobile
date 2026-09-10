import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/widgets/remote_image.dart';

/// Expansion set symbols are `.svg` and pack art is `.webp`.
/// `Image.network` can't decode SVG — it fails silently into its error
/// builder, which is why every set symbol in the app rendered as nothing.
void main() {
  group('isSvgUrl', () {
    test('recognises the catalog set symbols', () {
      expect(
        isSvgUrl('https://cdn2.pokepedia.id/set_svg/en/ancient-origins.svg'),
        isTrue,
      );
    });

    test('leaves raster art alone', () {
      expect(
        isSvgUrl('https://cdn2.pokepedia.id/en/ancient-origins.webp'),
        isFalse,
      );
      expect(isSvgUrl('https://cdn.pokepedia.id/AC3a/006_205.webp'), isFalse);
    });

    test('a query string does not hide the extension', () {
      // Signed or cache-busted URLs carry a query, so the decision has to
      // read the path rather than the whole string.
      expect(isSvgUrl('https://cdn2.pokepedia.id/a/aquapolis.svg?v=2'), isTrue);
      expect(isSvgUrl('https://cdn2.pokepedia.id/a/pack.webp?x=.svg'), isFalse);
    });

    test('extension case does not matter', () {
      expect(isSvgUrl('https://cdn2.pokepedia.id/a/SYMBOL.SVG'), isTrue);
    });

    test('a malformed url falls back to the raster path', () {
      expect(isSvgUrl('not a url at all'), isFalse);
    });
  });

  testWidgets('raster art renders through Image', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteImage(
            url: 'https://cdn2.pokepedia.id/en/ancient-origins.webp',
            height: 24,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });
}
