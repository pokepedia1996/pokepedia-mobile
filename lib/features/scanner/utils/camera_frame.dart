/// Turns a live camera frame into something the detector can read.
///
/// The two platforms hand back different things — Android streams YUV420, iOS
/// BGRA8888 — and neither is an RGB bitmap. This is the conversion, done once
/// per detector tick, so it is written to be cheap rather than general:
/// it samples straight to the target size instead of converting the full
/// frame and resizing after, which is the difference between touching ~2M
/// pixels and ~590k on a 1080p stream.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Long side the detector runs on.
///
/// The model squashes to 224×224 regardless, so anything above this is work
/// thrown away — and at 120ms per tick the conversion is the budget.
const detectMaxSide = 768;

/// Converts a frame to RGB, scaled so its long side is at most [maxSide].
///
/// Returns null for a format neither branch understands, which the caller
/// treats as a miss rather than an error — one unreadable frame among eight a
/// second is not worth surfacing.
img.Image? frameToImage(CameraImage frame, {int maxSide = detectMaxSide}) {
  // Dispatched on the plane layout rather than `format.group`. The group
  // reports what the controller *asked* for, which is not always what arrives
  // — and a mismatch there silently turns every frame into a miss, which
  // looks like a detector that never sees anything rather than a config bug.
  // Three planes is YUV420; one four-byte-per-pixel plane is BGRA.
  return decodePlanes(
    planes: [
      for (final plane in frame.planes)
        (
          bytes: plane.bytes,
          bytesPerRow: plane.bytesPerRow,
          bytesPerPixel: plane.bytesPerPixel,
        ),
    ],
    width: frame.width,
    height: frame.height,
    sensorOrientation: 0,
    maxSide: maxSide,
  );
}

/// One camera plane, in the parts an isolate can be handed.
typedef FramePlane = ({Uint8List bytes, int bytesPerRow, int? bytesPerPixel});

/// Decode + orient, from planes rather than a `CameraImage`.
///
/// This is the whole pixel-crunching half of a scanner tick, and it runs on
/// [DetectorWorker]'s isolate. Orientation is applied here so the caller
/// never holds an image in the wrong frame of reference.
img.Image? decodePlanes({
  required List<FramePlane> planes,
  required int width,
  required int height,
  required int sensorOrientation,
  int maxSide = detectMaxSide,
}) {
  final scale = math.min(1.0, maxSide / math.max(width, height).toDouble());
  final outWidth = math.max(1, (width * scale).round());
  final outHeight = math.max(1, (height * scale).round());

  final img.Image? decoded;
  // Dispatched on the plane layout rather than `format.group`: the group
  // reports what the controller *asked* for, which is not always what
  // arrives — and a mismatch there silently turns every frame into a miss.
  if (planes.length >= 3) {
    decoded = _yuv420ToImage(planes, width, height, outWidth, outHeight);
  } else if (planes.length == 1) {
    decoded = _bgraToImage(planes, width, height, outWidth, outHeight);
  } else {
    decoded = null;
  }
  if (decoded == null) return null;
  return orientFrame(decoded, sensorOrientation);
}

/// YUV420 (Android) → RGB, sampling directly at the output size.
///
/// The chroma planes are quarter-resolution and carry their own row stride and
/// pixel stride, both of which vary by device — reading them as a packed array
/// is the classic way this produces a green-tinted or sheared image.
img.Image? _yuv420ToImage(
  List<FramePlane> planes,
  int srcWidth,
  int srcHeight,
  int width,
  int height,
) {
  if (planes.length < 3) return null;

  final yPlane = planes[0];
  final uPlane = planes[1];
  final vPlane = planes[2];

  final yBytes = yPlane.bytes;
  final uBytes = uPlane.bytes;
  final vBytes = vPlane.bytes;

  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  final out = img.Image(width: width, height: height);
  final xRatio = srcWidth / width;
  final yRatio = srcHeight / height;

  for (var dy = 0; dy < height; dy++) {
    final sy = (dy * yRatio).floor().clamp(0, srcHeight - 1);
    final yRow = sy * yRowStride;
    final uvRow = (sy >> 1) * uvRowStride;

    for (var dx = 0; dx < width; dx++) {
      final sx = (dx * xRatio).floor().clamp(0, srcWidth - 1);

      final yIndex = yRow + sx;
      final uvIndex = uvRow + (sx >> 1) * uvPixelStride;
      if (yIndex >= yBytes.length ||
          uvIndex >= uBytes.length ||
          uvIndex >= vBytes.length) {
        continue;
      }

      final y = yBytes[yIndex];
      final u = uBytes[uvIndex] - 128;
      final v = vBytes[uvIndex] - 128;

      // BT.601, the range the camera stack produces.
      final r = (y + 1.402 * v).round().clamp(0, 255);
      final g = (y - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
      final b = (y + 1.772 * u).round().clamp(0, 255);

      out.setPixelRgb(dx, dy, r, g, b);
    }
  }
  return out;
}

/// BGRA8888 (iOS) → RGB, sampling directly at the output size.
img.Image? _bgraToImage(
  List<FramePlane> planes,
  int srcWidth,
  int srcHeight,
  int width,
  int height,
) {
  if (planes.isEmpty) return null;

  final plane = planes.first;
  final bytes = plane.bytes;
  final rowStride = plane.bytesPerRow;

  final out = img.Image(width: width, height: height);
  final xRatio = srcWidth / width;
  final yRatio = srcHeight / height;

  for (var dy = 0; dy < height; dy++) {
    final sy = (dy * yRatio).floor().clamp(0, srcHeight - 1);
    final row = sy * rowStride;

    for (var dx = 0; dx < width; dx++) {
      final sx = (dx * xRatio).floor().clamp(0, srcWidth - 1);
      final i = row + sx * 4;
      if (i + 2 >= bytes.length) continue;
      // B, G, R, A in memory order.
      out.setPixelRgb(dx, dy, bytes[i + 2], bytes[i + 1], bytes[i]);
    }
  }
  return out;
}

/// Rotates a frame so it matches what the user sees.
///
/// The sensor is mounted landscape on essentially every phone, so a frame
/// arrives 90° out from the portrait preview. The guide-free detector doesn't
/// strictly need upright input — the model tolerates a landscape card and the
/// aspect gate allows both orientations — but the *warp* does: an upside-down
/// or sideways card would be uploaded that way.
img.Image orientFrame(img.Image frame, int sensorOrientation) {
  final turns = ((sensorOrientation % 360) + 360) % 360;
  if (turns == 0) return frame;
  return img.copyRotate(frame, angle: turns);
}
