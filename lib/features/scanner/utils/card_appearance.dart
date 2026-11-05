import 'dart:typed_data';

import 'card_detector.dart';
import 'warp_quad.dart';

/// A small colour grid inside the card, sampled from the already prepared
/// tensor. Comparing card content lets a stack scan advance even when its
/// corners stay in the same position. This is a change signal, not identity.
List<double> cardAppearance(
  Float32List tensor,
  DetectRegion region,
  Quad quad,
) {
  const side = 8;
  const plane = modelInputSize * modelInputSize;
  const means = [0.485, 0.456, 0.406];
  const stds = [0.229, 0.224, 0.225];
  final values = <double>[];
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      // Stay inside the border to reduce sensitivity to sleeves and jitter.
      final u = 0.15 + (x + 0.5) / side * 0.7;
      final v = 0.15 + (y + 0.5) / side * 0.7;
      double interpolate(double a, double b, double c, double d) =>
          a * (1 - u) * (1 - v) + b * u * (1 - v) + c * u * v + d * (1 - u) * v;
      final px = interpolate(
        quad.topLeft.x,
        quad.topRight.x,
        quad.bottomRight.x,
        quad.bottomLeft.x,
      );
      final py = interpolate(
        quad.topLeft.y,
        quad.topRight.y,
        quad.bottomRight.y,
        quad.bottomLeft.y,
      );
      final sx = ((px - region.x) / region.width * modelInputSize)
          .floor()
          .clamp(0, modelInputSize - 1);
      final sy = ((py - region.y) / region.height * modelInputSize)
          .floor()
          .clamp(0, modelInputSize - 1);
      for (var c = 0; c < 3; c++) {
        var sum = 0.0;
        // Average a patch so a few pixels of corner jitter do not look like
        // different artwork, especially around printed text.
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            final tx = (sx + dx).clamp(0, modelInputSize - 1);
            final ty = (sy + dy).clamp(0, modelInputSize - 1);
            sum +=
                tensor[c * plane + ty * modelInputSize + tx] * stds[c] +
                means[c];
          }
        }
        values.add(sum / 25);
      }
    }
  }
  // Remove a global exposure shift while retaining colour and spatial detail.
  final mean = values.reduce((a, b) => a + b) / values.length;
  return values.map((v) => v - mean).toList(growable: false);
}

double appearanceDistance(List<double> a, List<double> b) {
  if (a.isEmpty || a.length != b.length) return double.infinity;
  var total = 0.0;
  for (var i = 0; i < a.length; i++) {
    total += (a[i] - b[i]).abs();
  }
  return total / a.length;
}
