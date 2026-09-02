import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/scanner/repository/models/scan_models.dart';
import 'package:pokepedia_mobile/features/scanner/utils/card_detector.dart';
import 'package:pokepedia_mobile/features/scanner/utils/warp_quad.dart';

/// A card-shaped quad at [cardAspect].
Quad _card({double x = 100, double y = 100, double w = 200}) => Quad([
  Point2(x, y),
  Point2(x + w, y),
  Point2(x + w, y + w / cardAspect),
  Point2(x, y + w / cardAspect),
]);

/// The nine raw outputs: eight normalised corner coords, then a presence
/// logit. Corner order is TL → TR → BR → BL.
List<double> _prediction({double presenceLogit = 3, List<double>? corners}) => [
  ...(corners ?? [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]),
  presenceLogit,
];

void main() {
  final frame = wholeFrame(1000, 1000);

  group('decodePrediction', () {
    test('maps normalised corners into the region they were detected in', () {
      final d = decodePrediction(
        _prediction(),
        regionOfTest(200, 400, 100, 50),
      );

      expect(d.quad.topLeft.x, closeTo(210, 0.01));
      expect(d.quad.topLeft.y, closeTo(405, 0.01));
      expect(d.quad.bottomRight.x, closeTo(290, 0.01));
      expect(d.quad.bottomRight.y, closeTo(445, 0.01));
    });

    test('holds the TL, TR, BR, BL order the model was trained on', () {
      // Scrambling this raises no error — it silently produces a garbled
      // warp, which is the handoff's own named gotcha.
      final d = decodePrediction(
        _prediction(corners: [0, 0, 1, 0, 1, 1, 0, 1]),
        frame,
      );

      expect(d.quad.topLeft, isA<Point2>());
      expect(d.quad.topLeft.x, 0);
      expect(d.quad.topLeft.y, 0);
      expect(d.quad.topRight.x, 1000);
      expect(d.quad.topRight.y, 0);
      expect(d.quad.bottomRight.x, 1000);
      expect(d.quad.bottomRight.y, 1000);
      expect(d.quad.bottomLeft.x, 0);
      expect(d.quad.bottomLeft.y, 1000);
    });

    test('presence is the sigmoid of the ninth output, not the raw logit', () {
      expect(
        decodePrediction(_prediction(presenceLogit: 0), frame).present,
        closeTo(0.5, 0.001),
      );
      expect(
        decodePrediction(_prediction(presenceLogit: 3), frame).present,
        greaterThan(0.9),
      );
      expect(
        decodePrediction(_prediction(presenceLogit: -3), frame).present,
        lessThan(0.1),
      );
    });
  });

  group('presence gate', () {
    test('rejects below the threshold', () {
      final d = Detection(present: 0.39, quad: _card());
      expect(passesGates(d, frame), isFalse);
    });

    test('accepts at the threshold', () {
      final d = Detection(present: minPresence, quad: _card());
      expect(passesGates(d, frame), isTrue);
    });
  });

  group('aspect gate', () {
    test('a card passes', () {
      expect(plausibleCardAspect(_card()), isTrue);
    });

    test('a landscape card passes too', () {
      // A card laid on its side is still a card; the warp squares it up.
      final landscape = Quad([
        const Point2(0, 0),
        const Point2(280, 0),
        const Point2(280, 200),
        const Point2(0, 200),
      ]);
      expect(landscape.impliedAspect, closeTo(1 / cardAspect, 0.01));
      expect(plausibleCardAspect(landscape), isTrue);
    });

    test('a long banner rejects', () {
      final banner = Quad([
        const Point2(0, 0),
        const Point2(600, 0),
        const Point2(600, 200),
        const Point2(0, 200),
      ]);
      expect(plausibleCardAspect(banner), isFalse);
    });

    test('the tolerance is loose enough to admit a square', () {
      // Not a bug and not worth tightening here: web widened this from 0.25
      // to 0.35 precisely because a tilted card measures a foreshortened
      // aspect, and the keystone and truncation gates are what carry the
      // rejection load. Pinned so a future tightening is a deliberate change
      // made on both sides rather than a drift.
      final square = Quad([
        const Point2(0, 0),
        const Point2(200, 0),
        const Point2(200, 200),
        const Point2(0, 200),
      ]);
      expect(plausibleCardAspect(square), isTrue);
      expect(
        plausibleCardAspect(square, tolerance: stage2AspectTolerance),
        isFalse,
      );
    });

    test('stage 2 holds a tighter bar than stage 1', () {
      // Its input is already zoomed and mostly frontal, so there is far less
      // foreshortening available to excuse a large aspect error.
      final off = Quad([
        const Point2(0, 0),
        const Point2(190, 0),
        const Point2(190, 200),
        const Point2(0, 200),
      ]);
      expect(plausibleCardAspect(off), isTrue);
      expect(
        plausibleCardAspect(off, tolerance: stage2AspectTolerance),
        isFalse,
      );
    });
  });

  group('truncation gate', () {
    test('a quad inside the region passes', () {
      expect(isQuadTruncated(_card(), frame), isFalse);
    });

    test('a corner past the edge rejects', () {
      // Presence fires confidently on a fragment of a card running off frame;
      // this is the gate that actually catches it.
      expect(isQuadTruncated(_card(x: -50), frame), isTrue);
    });

    test('the 2% tolerance absorbs a corner just touching the edge', () {
      final touching = _card(x: -15, y: 10, w: 200);
      expect(touching.topLeft.x, -15);
      expect(isQuadTruncated(touching, frame), isFalse);
    });
  });

  group('keystone gate', () {
    test('a rectangle is not keystoned', () {
      expect(isQuadKeystoned(_card()), isFalse);
    });

    test('a steep trapezoid rejects', () {
      final trapezoid = Quad([
        const Point2(80, 0),
        const Point2(120, 0),
        const Point2(200, 280),
        const Point2(0, 280),
      ]);
      expect(isQuadKeystoned(trapezoid), isTrue);
    });

    test('catches what the aspect gate averages away', () {
      // The aspect check averages opposite edges, which cancels exactly the
      // divergence a steep tilt produces — a trapezoid can land on a
      // card-like mean aspect and sail through it.
      final trapezoid = Quad([
        const Point2(60, 0),
        const Point2(140, 0),
        const Point2(200, 279),
        const Point2(0, 279),
      ]);
      expect(plausibleCardAspect(trapezoid), isTrue);
      expect(isQuadKeystoned(trapezoid), isTrue);
      expect(
        passesGates(Detection(present: 0.99, quad: trapezoid), frame),
        isFalse,
      );
    });
  });

  group('stage2Region', () {
    test('expands the bounding box by the margin', () {
      final region = stage2Region(_card(x: 300, y: 300, w: 200), 1000, 1000);

      expect(region.x, closeTo(300 - 40, 0.01));
      expect(region.width, closeTo(200 + 80, 0.01));
    });

    test('clamps to the frame rather than running off it', () {
      final region = stage2Region(_card(x: 10, y: 10, w: 200), 1000, 1000);
      expect(region.x, 0);
      expect(region.y, 0);
    });

    test('always has a positive extent', () {
      final degenerate = Quad([
        const Point2(5, 5),
        const Point2(5, 5),
        const Point2(5, 5),
        const Point2(5, 5),
      ]);
      final region = stage2Region(degenerate, 100, 100);
      expect(region.width, greaterThan(0));
      expect(region.height, greaterThan(0));
    });
  });
}

/// Local helper mirroring an explicit sub-region.
DetectRegion regionOfTest(double x, double y, double w, double h) =>
    DetectRegion(x, y, w, h);
