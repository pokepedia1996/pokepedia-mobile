import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pokepedia_mobile/features/scanner/utils/card_detector.dart';

/// A frame split into four solid quadrants, so any crop offset shows up as
/// the wrong colour rather than as a subtly wrong pixel.
img.Image _quadrants(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fillRect(
    im,
    x1: 0,
    y1: 0,
    x2: w ~/ 2 - 1,
    y2: h ~/ 2 - 1,
    color: img.ColorRgb8(255, 0, 0),
  );
  img.fillRect(
    im,
    x1: w ~/ 2,
    y1: 0,
    x2: w - 1,
    y2: h ~/ 2 - 1,
    color: img.ColorRgb8(0, 255, 0),
  );
  img.fillRect(
    im,
    x1: 0,
    y1: h ~/ 2,
    x2: w ~/ 2 - 1,
    y2: h - 1,
    color: img.ColorRgb8(0, 0, 255),
  );
  img.fillRect(
    im,
    x1: w ~/ 2,
    y1: h ~/ 2,
    x2: w - 1,
    y2: h - 1,
    color: img.ColorRgb8(255, 255, 255),
  );
  return im;
}

/// Reads one channel of the CHW tensor at a normalised position.
double _at(List<double> t, int channel, double u, double v) {
  const n = modelInputSize;
  final x = (u * (n - 1)).round();
  final y = (v * (n - 1)).round();
  return t[channel * n * n + y * n + x];
}

/// Which quadrant colour dominates at a normalised position: r, g, b or w.
String _colourAt(List<double> t, double u, double v) {
  final r = _at(t, 0, u, v);
  final g = _at(t, 1, u, v);
  final b = _at(t, 2, u, v);
  final high = [r, g, b].where((c) => c > 0).length;
  if (high >= 3) return 'w';
  if (r > g && r > b) return 'r';
  if (g > r && g > b) return 'g';
  return 'b';
}

void main() {
  group('prepareInput region cropping', () {
    test('a full-frame region samples the whole frame', () {
      final t = prepareInput(_quadrants(600, 400), wholeFrame(600, 400));

      expect(_colourAt(t, 0.25, 0.25), 'r');
      expect(_colourAt(t, 0.75, 0.25), 'g');
      expect(_colourAt(t, 0.25, 0.75), 'b');
      expect(_colourAt(t, 0.75, 0.75), 'w');
    });

    test('a sub-region samples only that sub-region', () {
      // The bottom-right quadrant alone: every sample must be white. An
      // offset bug shows up here as one of the other three colours.
      final t = prepareInput(
        _quadrants(600, 400),
        const DetectRegion(300, 200, 300, 200),
      );

      for (final u in [0.1, 0.5, 0.9]) {
        for (final v in [0.1, 0.5, 0.9]) {
          expect(_colourAt(t, u, v), 'w', reason: 'at ($u, $v)');
        }
      }
    });

    test('an off-centre sub-region keeps its own layout', () {
      // Straddling the vertical split: left half red, right half green.
      final t = prepareInput(
        _quadrants(600, 400),
        const DetectRegion(150, 0, 300, 200),
      );

      expect(_colourAt(t, 0.1, 0.5), 'r');
      expect(_colourAt(t, 0.9, 0.5), 'g');
    });

    test('the staged path lands on the same region as the direct one', () {
      // Staged resize triggers above a 2.5x downscale, and it is the branch
      // where a coordinate mistake would hide — it re-crops from a
      // *different* image than the direct path does.
      final big = _quadrants(2000, 2000);
      final small = _quadrants(400, 400);

      final staged = prepareInput(
        big,
        const DetectRegion(1000, 1000, 1000, 1000),
      );
      final direct = prepareInput(
        small,
        const DetectRegion(200, 200, 200, 200),
      );

      // Both are the bottom-right quadrant, so both must read white
      // throughout despite taking different code paths.
      for (final u in [0.2, 0.8]) {
        for (final v in [0.2, 0.8]) {
          expect(_colourAt(staged, u, v), 'w', reason: 'staged at ($u,$v)');
          expect(_colourAt(direct, u, v), 'w', reason: 'direct at ($u,$v)');
        }
      }
    });

    test('the tensor is CHW, not HWC', () {
      // A channel-interleaved buffer would still be the right length and
      // would still run — it would just predict nonsense.
      final t = prepareInput(_quadrants(400, 400), wholeFrame(400, 400));
      const plane = modelInputSize * modelInputSize;

      expect(t.length, 3 * plane);
      // Top-left is pure red: high in plane 0, low in planes 1 and 2.
      expect(t[0], greaterThan(t[plane]));
      expect(t[0], greaterThan(t[2 * plane]));
    });

    test('output is ImageNet-normalised, not raw 0-255', () {
      final t = prepareInput(_quadrants(400, 400), wholeFrame(400, 400));
      // Normalised values live roughly in [-2.2, 2.7]; raw bytes would not.
      expect(t.reduce((a, b) => a > b ? a : b), lessThan(3));
      expect(t.reduce((a, b) => a < b ? a : b), greaterThan(-3));
    });

    test('the resize squashes rather than preserving aspect', () {
      // Training used transforms.Resize((224,224)); preserving aspect would
      // letterbox and shift every predicted corner.
      final wide = img.Image(width: 800, height: 200);
      img.fill(wide, color: img.ColorRgb8(255, 0, 0));
      final t = prepareInput(wide, wholeFrame(800, 200));

      // Every corner is red — no letterbox bars anywhere.
      for (final u in [0.02, 0.98]) {
        for (final v in [0.02, 0.98]) {
          expect(_colourAt(t, u, v), 'r', reason: 'at ($u,$v)');
        }
      }
    });
  });
}
