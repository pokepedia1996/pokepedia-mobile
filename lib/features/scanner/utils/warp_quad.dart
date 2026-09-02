import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../repository/models/scan_models.dart';

/// Flattens a detected card quad into an upright, card-shaped image.
///
/// Ports `features/scanner/utils/warp-quad.ts`. The web hand-rolls an 8×8
/// homography solve because Canvas 2D only offers affine transforms; Dart has
/// the same gap. The `image` package's `copyRectify` looks like the answer and
/// isn't — it interpolates the four corners *bilinearly*, which bends straight
/// lines under perspective. A card photographed at an angle is exactly the
/// case that distinguishes the two, so the projective solve is done properly
/// here.
///
/// Corner order is TL → TR → BR → BL throughout. Getting it wrong produces no
/// error at all, just a scrambled output — see the handoff's gotcha #4.
class Quad {
  const Quad(this.corners);

  /// Exactly four points, TL → TR → BR → BL.
  final List<Point2> corners;

  Point2 get topLeft => corners[0];
  Point2 get topRight => corners[1];
  Point2 get bottomRight => corners[2];
  Point2 get bottomLeft => corners[3];

  double get topEdge => topLeft.distanceTo(topRight);
  double get bottomEdge => bottomLeft.distanceTo(bottomRight);
  double get leftEdge => topLeft.distanceTo(bottomLeft);
  double get rightEdge => topRight.distanceTo(bottomRight);

  /// Corner-to-corner span, used as the scale that drift is measured against —
  /// a quad filling the frame tolerates more absolute movement than a small
  /// one for the same apparent stability.
  double get diagonal => topLeft.distanceTo(bottomRight);

  /// Axis-aligned bounds, for the stage-2 re-crop.
  ({double left, double top, double right, double bottom}) get bounds {
    var left = corners.first.x;
    var right = corners.first.x;
    var top = corners.first.y;
    var bottom = corners.first.y;
    for (final c in corners) {
      left = math.min(left, c.x);
      right = math.max(right, c.x);
      top = math.min(top, c.y);
      bottom = math.max(bottom, c.y);
    }
    return (left: left, top: top, right: right, bottom: bottom);
  }

  /// The shape the quad implies, as width/height, comparing the averaged
  /// opposite edges.
  double get impliedAspect {
    final width = (topEdge + bottomEdge) / 2;
    final height = (leftEdge + rightEdge) / 2;
    if (height <= 0) return 0;
    return width / height;
  }

  /// Mean corner displacement between two quads as a fraction of this quad's
  /// own diagonal.
  ///
  /// Scale-relative on purpose: a fixed pixel threshold would read a card held
  /// close to the lens as unstable and one held far away as rock-steady, when
  /// both are the same hand.
  double driftFrom(Quad other) {
    final scale = diagonal;
    if (scale <= 0) return double.infinity;
    var total = 0.0;
    for (var i = 0; i < 4; i++) {
      total += corners[i].distanceTo(other.corners[i]);
    }
    return (total / 4) / scale;
  }

  /// Same quad in the coordinate space of the full frame, given the crop it
  /// was detected in.
  Quad offsetBy(double dx, double dy, {double scaleX = 1, double scaleY = 1}) {
    return Quad([
      for (final c in corners) Point2(c.x * scaleX + dx, c.y * scaleY + dy),
    ]);
  }
}

class Point2 {
  const Point2(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(Point2 other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// Long side ceiling for the warped output. Matches `captureMaxSide` — the
/// server downscales to a 1000px working side regardless.
const _warpMaxWidth = 1400;

/// Whether the quad describes a card lying on its side.
///
/// The aspect gate deliberately accepts both orientations — a card face-up on
/// a table is often sideways in frame, and so is every frame if the camera's
/// rotation is misread. The warp has to know which it is: mapping a landscape
/// quad onto a portrait rectangle squashes the card to about half its true
/// width, and the embedder returns *nothing* for the result. Measured, not
/// guessed — see `warp_quad_test.dart`.
bool isLandscapeQuad(Quad quad) => quad.impliedAspect > 1;

/// The output rectangle for a detected quad, in the quad's own orientation.
///
/// Ports the web's sizing: the wider of the two horizontal edges sets the
/// width (so the nearer edge of a tilted card governs and detail isn't thrown
/// away), capped, and the other dimension follows from [cardAspect] rather
/// than from the measured edges — the output is a card by definition, and
/// deriving it from a foreshortened edge would bake the tilt back in.
///
/// For a landscape quad the long edge is the card's *width*, so the rect is
/// landscape too; [warpQuad] turns it upright afterwards.
({int width, int height}) warpOutputSize(Quad quad) {
  final longest = math.max(quad.topEdge, quad.bottomEdge);
  final width = math.max(
    1,
    math.min(longest, _warpMaxWidth.toDouble()).round(),
  );
  final height = isLandscapeQuad(quad)
      ? math.max(1, (width * cardAspect).round())
      : math.max(1, (width / cardAspect).round());
  return (width: width, height: height);
}

/// Solves for the projective transform taking the unit rectangle's corners to
/// [quad], then samples [src] through it.
///
/// The 8 unknowns of a homography (the 9th is fixed by scale) come from 4
/// point correspondences, each giving 2 equations — hence the 8×8 system.
img.Image warpQuad(img.Image src, Quad quad) {
  final size = warpOutputSize(quad);
  final h = _solveHomography(
    size.width.toDouble(),
    size.height.toDouble(),
    quad,
  );
  final dst = img.Image(width: size.width, height: size.height);

  for (var y = 0; y < size.height; y++) {
    for (var x = 0; x < size.width; x++) {
      // Destination → source, so every output pixel is written exactly once;
      // the forward direction would leave holes wherever the map expands.
      final dx = x + 0.5;
      final dy = y + 0.5;
      final denom = h[6] * dx + h[7] * dy + 1;
      if (denom.abs() < 1e-9) continue;
      final sx = (h[0] * dx + h[1] * dy + h[2]) / denom;
      final sy = (h[3] * dx + h[4] * dy + h[5]) / denom;
      if (sx < 0 || sy < 0 || sx >= src.width || sy >= src.height) continue;
      dst.setPixel(
        x,
        y,
        src.getPixelInterpolate(
          sx,
          sy,
          interpolation: img.Interpolation.linear,
        ),
      );
    }
  }

  // Deliberately not rotated to portrait here, even though a landscape result
  // is upright only by luck. Which way to turn it depends on whether the model
  // labels corners by the card's own geometry or by their position in the
  // frame, and those need opposite rotations — measured on a real device,
  // 90° and 270° respectively. Guessing picks the wrong one half the time,
  // and web has no rotation guard either. What matters and *is* unambiguous
  // is the sizing above: squashing a landscape card into a portrait rect
  // takes recognition to zero matches.
  return dst;
}

/// The 8 homography coefficients mapping the output rectangle to [quad].
List<double> _solveHomography(double width, double height, Quad quad) {
  final dst = [
    const Point2(0, 0),
    Point2(width, 0),
    Point2(width, height),
    Point2(0, height),
  ];
  final src = quad.corners;

  // Each correspondence contributes two rows: one for x, one for y.
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final sx = src[i].x;
    final sy = src[i].y;
    final dx = dst[i].x;
    final dy = dst[i].y;

    a[i * 2] = [dx, dy, 1, 0, 0, 0, -dx * sx, -dy * sx, sx];
    a[i * 2 + 1] = [0, 0, 0, dx, dy, 1, -dx * sy, -dy * sy, sy];
  }
  return _gaussianSolve(a);
}

/// Gauss-Jordan with partial pivoting on an 8×9 augmented matrix.
///
/// Pivoting is not optional here: an axis-aligned quad puts exact zeros on the
/// diagonal, and without a row swap the elimination divides by one.
List<double> _gaussianSolve(List<List<double>> m) {
  const n = 8;
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var row = col + 1; row < n; row++) {
      if (m[row][col].abs() > m[pivot][col].abs()) pivot = row;
    }
    if (m[pivot][col].abs() < 1e-12) {
      // Degenerate (collinear corners). The identity leaves the frame
      // untouched, which is a visibly wrong crop rather than a crash — and
      // the gates upstream reject such quads before they reach here.
      return [1, 0, 0, 0, 1, 0, 0, 0];
    }
    if (pivot != col) {
      final tmp = m[col];
      m[col] = m[pivot];
      m[pivot] = tmp;
    }

    final div = m[col][col];
    for (var k = col; k <= n; k++) {
      m[col][k] /= div;
    }
    for (var row = 0; row < n; row++) {
      if (row == col) continue;
      final factor = m[row][col];
      if (factor == 0) continue;
      for (var k = col; k <= n; k++) {
        m[row][k] -= factor * m[col][k];
      }
    }
  }
  return [for (var i = 0; i < n; i++) m[i][n]];
}
