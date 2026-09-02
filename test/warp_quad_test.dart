import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pokepedia_mobile/features/scanner/repository/models/scan_models.dart';
import 'package:pokepedia_mobile/features/scanner/utils/warp_quad.dart';

Quad _rect(double l, double t, double r, double b) =>
    Quad([Point2(l, t), Point2(r, t), Point2(r, b), Point2(l, b)]);

void main() {
  group('warpOutputSize', () {
    test('height follows the card aspect, not the measured edges', () {
      // A tilted card's vertical edges are foreshortened; deriving height
      // from them would bake the tilt into the output. The quad here is
      // portrait but too short for its width, as a card leaning away reads.
      final quad = Quad([
        const Point2(0, 0),
        const Point2(100, 0),
        const Point2(100, 110),
        const Point2(0, 110),
      ]);
      final size = warpOutputSize(quad);

      expect(size.width, 100);
      expect(size.height, (100 / cardAspect).round());
    });

    test('the wider horizontal edge governs', () {
      // The near edge of a tilted card carries more detail than the far one.
      final quad = Quad([
        const Point2(0, 0),
        const Point2(60, 0),
        const Point2(100, 80),
        const Point2(-40, 80),
      ]);
      expect(warpOutputSize(quad).width, 140);
    });

    test('capped so a close-up card cannot balloon the upload', () {
      final quad = _rect(0, 0, 5000, 7000);
      expect(warpOutputSize(quad).width, 1400);
    });

    test('a degenerate quad still yields a usable size', () {
      expect(warpOutputSize(_rect(0, 0, 0, 0)).width, greaterThanOrEqualTo(1));
      expect(warpOutputSize(_rect(0, 0, 0, 0)).height, greaterThanOrEqualTo(1));
    });
  });

  group('warpQuad', () {
    /// A frame with a distinctly coloured marker in one corner region, so a
    /// scrambled corner order is visible rather than merely plausible.
    img.Image markedSource() {
      final src = img.Image(width: 200, height: 200);
      img.fill(src, color: img.ColorRgb8(0, 0, 0));
      // Top-left quadrant red, top-right green, bottom-right blue.
      img.fillRect(
        src,
        x1: 0,
        y1: 0,
        x2: 99,
        y2: 99,
        color: img.ColorRgb8(255, 0, 0),
      );
      img.fillRect(
        src,
        x1: 100,
        y1: 0,
        x2: 199,
        y2: 99,
        color: img.ColorRgb8(0, 255, 0),
      );
      img.fillRect(
        src,
        x1: 100,
        y1: 100,
        x2: 199,
        y2: 199,
        color: img.ColorRgb8(0, 0, 255),
      );
      return src;
    }

    test(
      'an axis-aligned quad round-trips its colours to the right corners',
      () {
        // The identity case: pivoting must handle the exact zeros an
        // axis-aligned quad puts on the diagonal.
        final out = warpQuad(markedSource(), _rect(0, 0, 200, 200));

        final tl = out.getPixel(out.width ~/ 8, out.height ~/ 8);
        final tr = out.getPixel(out.width * 7 ~/ 8, out.height ~/ 8);

        expect(tl.r, greaterThan(200), reason: 'top-left should be red');
        expect(tr.g, greaterThan(200), reason: 'top-right should be green');
      },
    );

    test('output carries the card aspect', () {
      final out = warpQuad(markedSource(), _rect(20, 20, 180, 180));
      expect(out.width / out.height, closeTo(cardAspect, 0.01));
    });

    test('a perspective quad maps straight lines to straight lines', () {
      // The property that separates a real homography from the bilinear
      // `copyRectify`: under a projective map the midpoint of a source edge
      // lands on the output edge, not bowed away from it.
      final src = img.Image(width: 200, height: 200);
      img.fill(src, color: img.ColorRgb8(0, 0, 0));
      // A white band down the middle of the source.
      img.fillRect(
        src,
        x1: 95,
        y1: 0,
        x2: 105,
        y2: 199,
        color: img.ColorRgb8(255, 255, 255),
      );

      // Trapezoid: top edge narrower than the bottom, i.e. a card leaning back.
      final out = warpQuad(
        src,
        Quad([
          const Point2(60, 0),
          const Point2(140, 0),
          const Point2(200, 200),
          const Point2(0, 200),
        ]),
      );

      // The band runs down the source's centre, so it must stay centred at
      // every height of the output — a bilinear map would let it wander.
      for (final fraction in [0.2, 0.5, 0.8]) {
        final y = (out.height * fraction).round();
        final centre = out.getPixel(out.width ~/ 2, y);
        expect(
          centre.r,
          greaterThan(128),
          reason: 'band should stay centred at ${fraction * 100}% height',
        );
      }
    });

    test('collinear corners degrade rather than crash', () {
      final flat = Quad([
        const Point2(0, 0),
        const Point2(100, 0),
        const Point2(200, 0),
        const Point2(300, 0),
      ]);
      expect(() => warpQuad(markedSource(), flat), returnsNormally);
    });
  });

  group('Quad geometry', () {
    test('implied aspect averages opposite edges', () {
      final quad = _rect(0, 0, 71.59, 100);
      expect(quad.impliedAspect, closeTo(cardAspect, 0.001));
    });

    test('drift is scale-relative, not absolute pixels', () {
      // The same 5px hand tremor is steady on a close-up card and severe on
      // a distant one; a pixel threshold would get both backwards.
      final near = _rect(0, 0, 400, 560);
      final nearMoved = _rect(5, 5, 405, 565);
      final far = _rect(0, 0, 40, 56);
      final farMoved = _rect(5, 5, 45, 61);

      expect(near.driftFrom(nearMoved), lessThan(far.driftFrom(farMoved)));
    });

    test('an identical quad has zero drift', () {
      final quad = _rect(10, 10, 110, 150);
      expect(quad.driftFrom(_rect(10, 10, 110, 150)), 0);
    });

    test('bounds cover every corner', () {
      final quad = Quad([
        const Point2(30, 5),
        const Point2(90, 20),
        const Point2(80, 120),
        const Point2(10, 100),
      ]);
      final b = quad.bounds;

      expect(b.left, 10);
      expect(b.top, 5);
      expect(b.right, 90);
      expect(b.bottom, 120);
    });

    test('offsetBy moves a crop-space quad into frame space', () {
      final quad = _rect(0, 0, 10, 20).offsetBy(100, 50, scaleX: 2, scaleY: 3);
      expect(quad.topLeft.x, 100);
      expect(quad.topLeft.y, 50);
      expect(quad.bottomRight.x, 120);
      expect(quad.bottomRight.y, 110);
    });
  });

  group('quad orientation', () {
    test('a sideways card is recognised as landscape', () {
      // The aspect gate accepts both orientations, so the warp is where the
      // distinction has to be made.
      final landscape = Quad([
        const Point2(0, 0),
        const Point2(431, 0),
        const Point2(431, 309),
        const Point2(0, 309),
      ]);
      expect(isLandscapeQuad(landscape), isTrue);
      expect(isLandscapeQuad(_rect(0, 0, 309, 431)), isFalse);
    });

    test('a landscape quad keeps the card\'s proportions', () {
      // Measured against the live embedder: mapping a 1.4:1 quad onto a
      // portrait rect squashes the card to about half its true width and
      // returns *zero* matches — not a worse match, none at all.
      final landscape = Quad([
        const Point2(0, 0),
        const Point2(431, 0),
        const Point2(431, 309),
        const Point2(0, 309),
      ]);
      final size = warpOutputSize(landscape);

      expect(size.width, 431);
      expect(size.height, (431 * cardAspect).round());
      expect(size.width / size.height, closeTo(1 / cardAspect, 0.01));
    });

    test('a portrait quad is unchanged by the landscape branch', () {
      final size = warpOutputSize(_rect(0, 0, 309, 431));
      expect(size.width / size.height, closeTo(cardAspect, 0.01));
    });

    test('the cap applies in both orientations', () {
      final wide = Quad([
        const Point2(0, 0),
        const Point2(5000, 0),
        const Point2(5000, 3000),
        const Point2(0, 3000),
      ]);
      expect(warpOutputSize(wide).width, 1400);
      expect(warpOutputSize(_rect(0, 0, 5000, 7000)).width, 1400);
    });
  });
}
