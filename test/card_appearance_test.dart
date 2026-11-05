import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/scanner/utils/card_appearance.dart';
import 'package:pokepedia_mobile/features/scanner/utils/card_detector.dart';
import 'package:pokepedia_mobile/features/scanner/utils/warp_quad.dart';

Float32List tensor({double exposure = 0, bool swapped = false}) {
  const means = [0.485, 0.456, 0.406], stds = [0.229, 0.224, 0.225];
  const size = modelInputSize * modelInputSize;
  final result = Float32List(size * 3);
  for (var c = 0; c < 3; c++) {
    for (var y = 0; y < modelInputSize; y++) {
      for (var x = 0; x < modelInputSize; x++) {
        final high = swapped ? y < 112 : x < 112;
        final colour = (high ? 0.7 : 0.2) + exposure;
        result[c * size + y * modelInputSize + x] =
            (colour - means[c]) / stds[c];
      }
    }
  }
  return result;
}

void main() {
  const region = DetectRegion(0, 0, 224, 224);
  const quad = Quad([
    Point2(20, 10),
    Point2(204, 10),
    Point2(204, 214),
    Point2(20, 214),
  ]);
  test('global exposure changes do not signal replacement', () {
    final a = cardAppearance(tensor(), region, quad);
    final b = cardAppearance(tensor(exposure: 0.1), region, quad);
    expect(appearanceDistance(a, b), lessThan(0.001));
  });
  test('small corner jitter stays below replacement threshold', () {
    final input = tensor();
    final a = cardAppearance(input, region, quad);
    final b = cardAppearance(input, region, quad.offsetBy(2, 2));
    expect(appearanceDistance(a, b), lessThan(0.06));
  });
  test(
    'different artwork at identical corners exceeds replacement threshold',
    () {
      final a = cardAppearance(tensor(), region, quad);
      final b = cardAppearance(tensor(swapped: true), region, quad);
      expect(appearanceDistance(a, b), greaterThan(0.12));
    },
  );
}
