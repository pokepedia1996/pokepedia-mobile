/// Client-side card-corner detection. Ports
/// `features/scanner/utils/card-detector.ts`.
///
/// The model is a small corner regressor: given a 224×224 crop it predicts the
/// card's four corners plus a presence logit. Everything here except the
/// inference call itself is pure arithmetic, and deliberately so — the
/// preprocessing has to reproduce the training pipeline *exactly* or the
/// predictions drift, and that is far easier to hold to when it can be tested
/// without a model loaded.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../repository/models/scan_models.dart';
import 'warp_quad.dart';

/// The model's fixed input side.
const modelInputSize = 224;

/// Eight of the nine outputs are corner coordinates; the ninth is presence.
const _cornerValueCount = 8;

/// ImageNet normalisation, matching training.
const _imagenetMean = [0.485, 0.456, 0.406];
const _imagenetStd = [0.229, 0.224, 0.225];

/// The photometric filter every training image went through
/// (`apply_client_pipeline()` in `build_corner_dataset.py`). Without it the
/// live frame sits off the distribution the model learned.
const _brightness = 1.2;
const _contrast = 1.05;

/// Downscale factor past which the resize is staged through an intermediate.
///
/// A single huge downsample aliases — it point-samples a handful of source
/// pixels per output pixel and misses the card's edges entirely, which is
/// exactly the signal being regressed.
const _stagedResizeTrigger = 2.5;
const _stagedResizeIntermediateSide = 512;

/// Presence below this is "no card in view".
const minPresence = 0.4;

/// How far the implied aspect may sit from a card's before the quad is
/// rejected. Loose on purpose: a genuinely tilted card measures a
/// foreshortened aspect before warping, and this gate was rejecting exactly
/// those.
const modelAspectTolerance = 0.35;

/// Stage 2 sees an already-zoomed, mostly-frontal crop, so there is far less
/// foreshortening available to explain a large aspect error.
const stage2AspectTolerance = 0.15;

/// Fraction of the crop a corner may sit outside before the quad counts as
/// truncated.
const truncationTolerance = 0.02;

/// Maximum divergence between opposite edges before the quad reads as
/// keystoned rather than card-like.
const maxKeystoneRatio = 0.4;

/// Margin added around stage 1's bounding box for the stage-2 crop.
const stage2MarginFraction = 0.2;

/// A region of a frame, in that frame's pixels.
class DetectRegion {
  const DetectRegion(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;
}

/// A raw model prediction, in the coordinate space of the frame it was run on.
class Detection {
  const Detection({required this.present, required this.quad});

  /// Sigmoid of the presence logit, 0–1.
  final double present;
  final Quad quad;
}

double sigmoid(double x) => 1 / (1 + math.exp(-x));

/// Builds the CHW float tensor the model expects from a region of [source].
///
/// [region] is in source pixels. The resize is a squash, not a fit — it
/// matches `transforms.Resize((224, 224))` in training, and preserving aspect
/// here would present the model with letterboxing it never saw.
Float32List prepareInput(img.Image source, DetectRegion region) {
  final downscale =
      math.max(region.width, region.height) / modelInputSize.toDouble();

  var working = source;
  var rect = region;

  if (downscale > _stagedResizeTrigger) {
    final scale =
        _stagedResizeIntermediateSide / math.max(region.width, region.height);
    final cropped = img.copyCrop(
      source,
      x: region.x.round(),
      y: region.y.round(),
      width: math.max(1, region.width.round()),
      height: math.max(1, region.height.round()),
    );
    working = img.copyResize(
      cropped,
      width: math.max(1, (region.width * scale).round()),
      height: math.max(1, (region.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
    rect = DetectRegion(
      0,
      0,
      working.width.toDouble(),
      working.height.toDouble(),
    );
  }

  final crop = img.copyCrop(
    working,
    x: rect.x.round(),
    y: rect.y.round(),
    width: math.max(1, rect.width.round()),
    height: math.max(1, rect.height.round()),
  );
  final resized = img.copyResize(
    crop,
    width: modelInputSize,
    height: modelInputSize,
    interpolation: img.Interpolation.linear,
  );

  const size = modelInputSize * modelInputSize;
  final out = Float32List(3 * size);
  for (var y = 0; y < modelInputSize; y++) {
    for (var x = 0; x < modelInputSize; x++) {
      final p = resized.getPixel(x, y);
      final i = y * modelInputSize + x;
      out[i] = _normalize(p.r.toDouble(), 0);
      out[size + i] = _normalize(p.g.toDouble(), 1);
      out[2 * size + i] = _normalize(p.b.toDouble(), 2);
    }
  }
  return out;
}

/// Applies the brightness/contrast filter, scales to 0–1, then ImageNet
/// normalises — in that order, which is the order training used.
double _normalize(double channel, int index) {
  // CSS `brightness()` is a plain multiply; `contrast()` pivots around 0.5.
  var v = channel / 255 * _brightness;
  v = (v - 0.5) * _contrast + 0.5;
  v = v.clamp(0.0, 1.0);
  return (v - _imagenetMean[index]) / _imagenetStd[index];
}

/// A region of a frame, in that frame's pixels.
/// Turns the model's 9 raw outputs into a [Detection] in frame space.
///
/// The corner order the model was trained on is TL → TR → BR → BL. Reordering
/// it produces no error, only a scrambled warp, so it is fixed here and
/// nowhere else.
Detection decodePrediction(List<double> prediction, DetectRegion region) {
  final present = sigmoid(prediction[_cornerValueCount]);
  final corners = <Point2>[];
  for (var i = 0; i < _cornerValueCount; i += 2) {
    corners.add(
      Point2(
        region.x + prediction[i] * region.width,
        region.y + prediction[i + 1] * region.height,
      ),
    );
  }
  return Detection(present: present, quad: Quad(corners));
}

/// Whether the quad's implied aspect could be a card.
///
/// Both orientations are allowed — a card laid landscape is still a card, and
/// the warp squares it up either way.
bool plausibleCardAspect(Quad quad, {double tolerance = modelAspectTolerance}) {
  final aspect = quad.impliedAspect;
  if (aspect <= 0) return false;
  return (aspect - cardAspect).abs() <= tolerance ||
      (aspect - 1 / cardAspect).abs() <= tolerance;
}

/// Whether any corner sits outside the crop it was detected in.
///
/// A real truncation signal, unlike presence, which fires confidently on a
/// fragment of a card that runs off the edge of the frame.
bool isQuadTruncated(
  Quad quad,
  DetectRegion region, {
  double tolerance = truncationTolerance,
}) {
  final tolX = region.width * tolerance;
  final tolY = region.height * tolerance;
  return quad.corners.any(
    (p) =>
        p.x < region.x - tolX ||
        p.x > region.x + region.width + tolX ||
        p.y < region.y - tolY ||
        p.y > region.y + region.height + tolY,
  );
}

/// Whether opposite edges diverge too far to be a card seen at a sane angle.
///
/// [plausibleCardAspect] averages the opposite edges, which cancels out
/// exactly the divergence a steep tilt produces — a strongly trapezoidal quad
/// can land on a perfectly card-like mean aspect and pass it. This compares
/// the pairs directly instead.
bool isQuadKeystoned(Quad quad, {double maxRatio = maxKeystoneRatio}) {
  final widthMean = (quad.topEdge + quad.bottomEdge) / 2;
  final heightMean = (quad.leftEdge + quad.rightEdge) / 2;
  final widthDivergence =
      (quad.topEdge - quad.bottomEdge).abs() / (widthMean == 0 ? 1 : widthMean);
  final heightDivergence =
      (quad.leftEdge - quad.rightEdge).abs() /
      (heightMean == 0 ? 1 : heightMean);
  return widthDivergence > maxRatio || heightDivergence > maxRatio;
}

/// The reject gates, in the order the handoff specifies — first match rejects.
///
/// Order matters for cost, not just correctness: presence is a single compare
/// and throws out the common "nothing in view" case before any geometry runs.
bool passesGates(
  Detection detection,
  DetectRegion region, {
  double aspectTolerance = modelAspectTolerance,
}) {
  if (detection.present < minPresence) return false;
  if (!plausibleCardAspect(detection.quad, tolerance: aspectTolerance)) {
    return false;
  }
  if (isQuadTruncated(detection.quad, region)) return false;
  if (isQuadKeystoned(detection.quad)) return false;
  return true;
}

/// The stage-2 crop for a stage-1 quad: its bounding box, expanded, clamped to
/// the frame.
///
/// The margin is wide enough that a coarse stage-1 box slightly too tight
/// still leaves the card's true edges inside stage 2's view, and tight enough
/// that stage 2 is meaningfully zoomed in — which is the entire point of
/// splitting the passes.
DetectRegion stage2Region(Quad quad, int frameWidth, int frameHeight) {
  final b = quad.bounds;
  final marginX = (b.right - b.left) * stage2MarginFraction;
  final marginY = (b.bottom - b.top) * stage2MarginFraction;

  final left = math.max(0.0, b.left - marginX);
  final top = math.max(0.0, b.top - marginY);
  final right = math.min(frameWidth.toDouble(), b.right + marginX);
  final bottom = math.min(frameHeight.toDouble(), b.bottom + marginY);

  return DetectRegion(
    left,
    top,
    math.max(1.0, right - left),
    math.max(1.0, bottom - top),
  );
}

/// A region covering a whole frame.
DetectRegion wholeFrame(int width, int height) =>
    DetectRegion(0, 0, width.toDouble(), height.toDouble());
