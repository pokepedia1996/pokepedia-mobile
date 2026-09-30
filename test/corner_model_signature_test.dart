import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_litert/flutter_litert.dart' show Interpreter;
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/scanner/utils/card_detector.dart';

/// The bundled model is loaded through LiteRT rather than ONNX Runtime now.
/// Everything in `card_detector.dart` — the ImageNet normalisation, the CHW
/// packing, the staged resize — reproduces the training pipeline for a
/// specific input signature, and a converted model that quietly came out
/// NHWC, or quantised to int8, would still load and still return numbers.
/// They would just be wrong, in a way only a scan in the hand would show.
/// So the signature is asserted here rather than trusted.
void main() {
  test(
    'the bundled tflite model has the signature the detector prepares for',
    () {
      final bytes = File('assets/models/card_corners.tflite').readAsBytesSync();
      final interpreter = Interpreter.fromBuffer(Uint8List.fromList(bytes));
      addTearDown(interpreter.close);

      final input = interpreter.getInputTensors().single;
      final output = interpreter.getOutputTensors().single;

      // NCHW, not NHWC: `prepareInput` packs channel-planar.
      expect(input.shape, [1, 3, modelInputSize, modelInputSize]);
      expect(input.type.toString(), contains('float32'));

      // Eight corner coordinates plus the presence logit.
      expect(output.shape, [1, 9]);
      expect(output.type.toString(), contains('float32'));
    },
  );

  test('it runs, and the flat Float32List shapes are accepted as-is', () {
    final bytes = File('assets/models/card_corners.tflite').readAsBytesSync();
    final interpreter = Interpreter.fromBuffer(Uint8List.fromList(bytes));
    addTearDown(interpreter.close);

    final input = Float32List(3 * modelInputSize * modelInputSize);
    final output = Float32List(9);
    interpreter.run(input, output);

    // A grey field is not a card, so nothing is asserted about the corners —
    // only that the run completed and wrote real numbers back.
    expect(output.length, 9);
    expect(output.every((v) => v.isFinite), isTrue);
  });
}
