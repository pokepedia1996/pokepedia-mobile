import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../repository/models/scan_models.dart';

/// Turns a raw camera still into the tight, card-shaped crop `/api/scan`
/// expects.
///
/// ## Why this file carries the accuracy of the whole feature
///
/// The embedder does **no** server-side detection — `embedder.py`'s `/scan`
/// reports `detection_source: "disabled"`, and its docstring is explicit that
/// the client "already warps a tight card crop before upload … or declines to
/// capture at all". Whatever this produces is embedded and compared against
/// catalog renders as-is, so a loose or wrongly-proportioned crop doesn't
/// degrade gracefully: it shifts the query vector away from every catalog
/// entry at once and the scan reads as "not recognized".
///
/// ## How this differs from the web, deliberately
///
/// The web finds the card itself, running a two-stage ONNX corner regressor
/// over the live feed (`utils/card-detector.ts`) and perspective-warping the
/// detected quad (`utils/warp-quad.ts`). That path costs a ~5.7 MB model and a
/// ~2.7 MB WASM runtime, both of which a browser fetches once and caches.
///
/// This port instead makes the *user* the detector: a fixed card-aspect guide
/// box is drawn on the preview, the user fills it, and capture crops exactly
/// that rectangle. The trade is deliberate — it gives up automatic detection
/// (and with it perspective correction for a tilted card) in exchange for no
/// model download, no inference budget per frame, and a crop whose geometry is
/// known exactly rather than predicted. It lands in the same framing the web's
/// own detector was tuned around: `card-detector.ts` notes stage 2 exists to
/// reproduce "the same near-filling framing the original guide-box model was
/// good at". A device-side corner model can be slotted in later behind
/// [cropCardFromFrame]'s signature without the rest of the feature changing.
///
/// The cost of that trade is real and worth naming: a card held at a steep
/// angle is never straightened here, so it embeds worse than it would on the
/// web. The guide box is what keeps that from mattering in practice — a card
/// aligned to a drawn rectangle is close to frontal by construction.

/// Long side of the uploaded crop.
///
/// The server resizes to a 1000px working side before the embedder sees it
/// (`scan.server.ts`), so anything above that is upload cost the embedder
/// immediately discards. Kept a little above 1000, like the web's own
/// `CAPTURE_MAX_SIDE`, so the final downscale is done by the server's Lanczos
/// resize rather than this one.
const captureMaxSide = 1400;

/// JPEG quality for the upload. Matches the web's 0.92 WebP — high enough that
/// compression artifacts don't perturb the embedding, low enough to keep the
/// request well under `/api/scan`'s 4.5 MB cap.
const _captureJpegQuality = 92;

/// Mean luma below which the crop gets a brightness lift before upload, so a
/// dim indoor scan isn't embedded near-black. Ports `DIM_CAPTURE_LUMA`.
const _dimCaptureLuma = 90.0;

/// Side of the square the focus score is measured on. Sampling rather than
/// scoring full resolution keeps the Laplacian pass cheap; ports
/// `SHARPNESS_SAMPLE_SIDE`.
const _sharpnessSampleSide = 64;

/// A finished capture, ready to upload.
class CardCapture {
  const CardCapture({
    required this.bytes,
    required this.sharpness,
    required this.luma,
    required this.width,
    required this.height,
  });

  /// JPEG, cropped to [cardAspect] and capped at [captureMaxSide].
  final Uint8List bytes;

  /// Laplacian variance of the crop — the focus score. Compared against
  /// [captureMinSharpness] to tell a genuinely blurry capture apart from a
  /// sharp miss.
  final double sharpness;

  /// Mean luma, 0-255.
  final double luma;

  final int width;
  final int height;
}

/// Where the guide box sits inside the captured image, in image pixels.
///
/// The preview is rendered with `BoxFit.cover`, so part of the sensor frame is
/// off-screen; the guide box the user aligned against is positioned in *screen*
/// space. Mapping one to the other is what this does — get it wrong and every
/// crop is offset, which looks exactly like a recognition problem.
///
/// [previewSize] is the camera frame's size **as displayed** (i.e. already
/// rotated to portrait if that's how it's shown), [screenSize] the box it's
/// painted into, and [guideRect] the guide box in that same screen space.
Rect guideRectInImageSpace({
  required Size previewSize,
  required Size screenSize,
  required Rect guideRect,
}) {
  // `cover` scales by whichever axis needs the most magnification, then
  // centres — so the overflow is split evenly on both sides of that axis.
  final scale = math.max(
    screenSize.width / previewSize.width,
    screenSize.height / previewSize.height,
  );
  final displayedWidth = previewSize.width * scale;
  final displayedHeight = previewSize.height * scale;
  final offsetX = (screenSize.width - displayedWidth) / 2;
  final offsetY = (screenSize.height - displayedHeight) / 2;

  return Rect.fromLTRB(
    (guideRect.left - offsetX) / scale,
    (guideRect.top - offsetY) / scale,
    (guideRect.right - offsetX) / scale,
    (guideRect.bottom - offsetY) / scale,
  );
}

/// Arguments for the off-thread crop. A single object because `compute` takes
/// exactly one.
class _CropRequest {
  const _CropRequest({
    required this.bytes,
    required this.cropLeftFraction,
    required this.cropTopFraction,
    required this.cropWidthFraction,
    required this.cropHeightFraction,
  });

  final Uint8List bytes;

  /// The crop rect as fractions of the decoded image, not absolute pixels —
  /// the caller measures against the preview's dimensions, which need not
  /// match the still's (many sensors hand back a higher-resolution photo than
  /// the preview stream). Fractions survive that mismatch; pixels wouldn't.
  final double cropLeftFraction;
  final double cropTopFraction;
  final double cropWidthFraction;
  final double cropHeightFraction;
}

/// Decodes, crops to the guide box, snaps to [cardAspect], and encodes.
///
/// Runs on a background isolate — decoding a 12MP JPEG and resampling it takes
/// long enough to drop frames if done on the UI thread, and this happens on
/// every capture.
Future<CardCapture?> cropCardFromFrame({
  required Uint8List frameBytes,
  required Rect cropRectInImageSpace,
  required Size imageSize,
}) {
  if (imageSize.width <= 0 || imageSize.height <= 0) return Future.value(null);
  return compute(
    _cropCardSync,
    _CropRequest(
      bytes: frameBytes,
      cropLeftFraction: cropRectInImageSpace.left / imageSize.width,
      cropTopFraction: cropRectInImageSpace.top / imageSize.height,
      cropWidthFraction: cropRectInImageSpace.width / imageSize.width,
      cropHeightFraction: cropRectInImageSpace.height / imageSize.height,
    ),
  );
}

CardCapture? _cropCardSync(_CropRequest request) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(request.bytes);
  } on Exception {
    return null;
  } on RangeError {
    return null;
  }
  if (decoded == null) return null;

  // The still carries an EXIF orientation tag on most Android sensors, and the
  // crop fractions were measured against the *upright* preview. Baking it here
  // rather than relying on the server's `sharp().rotate()` keeps those two in
  // the same coordinate space — and the re-encode below writes no orientation
  // tag, so the server would have nothing to rotate by anyway.
  final upright = img.bakeOrientation(decoded);

  final left = (request.cropLeftFraction * upright.width).round();
  final top = (request.cropTopFraction * upright.height).round();
  final width = (request.cropWidthFraction * upright.width).round();
  final height = (request.cropHeightFraction * upright.height).round();

  // Clamped rather than trusted: a guide box can extend past the frame on a
  // preview whose aspect differs from the still's, and copyCrop on an
  // out-of-bounds rect yields garbage edges rather than an error.
  final safeLeft = left.clamp(0, math.max(0, upright.width - 1));
  final safeTop = top.clamp(0, math.max(0, upright.height - 1));
  final safeWidth = width.clamp(1, upright.width - safeLeft);
  final safeHeight = height.clamp(1, upright.height - safeTop);

  var card = img.copyCrop(
    upright,
    x: safeLeft,
    y: safeTop,
    width: safeWidth,
    height: safeHeight,
  );

  // Force the known card proportions rather than whatever the clamp above left
  // behind. Ports `snapToCardAspect`: the catalog renders this is compared
  // against are all exactly [cardAspect], so a crop even slightly off-ratio
  // embeds as a subtly stretched card.
  card = _snapToCardAspect(card);

  final longSide = math.max(card.width, card.height);
  if (longSide > captureMaxSide) {
    final scale = captureMaxSide / longSide;
    card = img.copyResize(
      card,
      width: (card.width * scale).round(),
      height: (card.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  final measured = _laplacianVarianceAndLuma(card);

  // Unconditional brightening would clip white borders and blow out holo foil,
  // so it only applies to a genuinely dim frame — same gate as the web's.
  if (measured.luma < _dimCaptureLuma) {
    card = img.adjustColor(card, brightness: 1.2, contrast: 1.05);
  }

  return CardCapture(
    bytes: img.encodeJpg(card, quality: _captureJpegQuality),
    sharpness: measured.variance,
    luma: measured.luma,
    width: card.width,
    height: card.height,
  );
}

/// Resamples to exactly [cardAspect], keeping the long side. Ports the web's
/// `snapToCardAspect`.
img.Image _snapToCardAspect(img.Image source) {
  final portrait = source.height >= source.width;
  final longSide = math.max(source.width, source.height);
  final shortSide = (longSide * cardAspect).round();
  final targetWidth = portrait ? shortSide : longSide;
  final targetHeight = portrait ? longSide : shortSide;
  if (targetWidth == source.width && targetHeight == source.height) {
    return source;
  }
  return img.copyResize(
    source,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.average,
  );
}

/// Laplacian variance as a cheap focus score, with mean luma riding the same
/// grayscale pass. Ports `laplacianVarianceAndLuma`.
({double variance, double luma}) _laplacianVarianceAndLuma(img.Image source) {
  final sample = img.copyResize(
    source,
    width: _sharpnessSampleSide,
    height: _sharpnessSampleSide,
    interpolation: img.Interpolation.average,
  );
  final int width = sample.width;
  final int height = sample.height;
  final gray = Float32List(width * height);
  var lumaSum = 0.0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = sample.getPixel(x, y);
      // Rec. 601 luma, the same weights the web's canvas pass uses.
      final double value =
          0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      gray[y * width + x] = value;
      lumaSum += value;
    }
  }
  final luma = lumaSum / (width * height);

  var sum = 0.0;
  var sumSq = 0.0;
  var count = 0;
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final i = y * width + x;
      final lap =
          gray[i - 1] +
          gray[i + 1] +
          gray[i - width] +
          gray[i + width] -
          4 * gray[i];
      sum += lap;
      sumSq += lap * lap;
      count++;
    }
  }
  if (count == 0) return (variance: 0, luma: luma);
  final mean = sum / count;
  return (variance: sumSq / count - mean * mean, luma: luma);
}
