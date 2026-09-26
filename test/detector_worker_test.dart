import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/scanner/utils/camera_frame.dart';
import 'package:pokepedia_mobile/features/scanner/utils/card_detector.dart';
import 'package:pokepedia_mobile/features/scanner/utils/detector_worker.dart';

/// The scanner's per-tick pixel work moved off the UI isolate. What has to
/// survive that move is the decode itself: same pixels, same orientation,
/// same tensor — only computed somewhere else.
List<FramePlane> _bgraPlanes(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      bytes[i] = 20; // B
      bytes[i + 1] = 140; // G
      bytes[i + 2] = 230; // R
      bytes[i + 3] = 255;
    }
  }
  return [(bytes: bytes, bytesPerRow: width * 4, bytesPerPixel: 4)];
}

/// Alternating black and white: all edges, so its Laplacian variance is high.
List<FramePlane> _checkerPlanes(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final on = (x + y).isEven ? 255 : 0;
      bytes[i] = on;
      bytes[i + 1] = on;
      bytes[i + 2] = on;
      bytes[i + 3] = 255;
    }
  }
  return [(bytes: bytes, bytesPerRow: width * 4, bytesPerPixel: 4)];
}

void main() {
  // The decode is a pure function and was easy to cover; the worker around
  // it was not covered at all, and that is where it broke. `spawn` threw on
  // a second `listen` to a single-subscription port, `initState` swallowed
  // it, and every tick then returned early — a scanner that saw nothing.
  group('the worker itself', () {
    test('spawns, and answers with a tensor', () async {
      final worker = await DetectorWorker.spawn();
      addTearDown(worker.dispose);

      final prep = await worker.prepareFrameForTest(
        planes: _bgraPlanes(320, 240),
        width: 320,
        height: 240,
        sensorOrientation: 0,
      );

      expect(prep, isNotNull);
      expect(prep!.width, 320);
      expect(prep.height, 240);
      expect(prep.tensor.length, 3 * modelInputSize * modelInputSize);
      // The rect the tensor was cut from comes back with it: the corners
      // are fractions of *that*, so decoding against any other one puts the
      // quad somewhere the card is not.
      expect(prep.region.width, greaterThan(0));
    });

    test('answers a second request against the frame it kept', () async {
      final worker = await DetectorWorker.spawn();
      addTearDown(worker.dispose);

      await worker.prepareFrameForTest(
        planes: _bgraPlanes(320, 240),
        width: 320,
        height: 240,
        sensorOrientation: 0,
      );

      // Stage two never sends the frame again — it is already there.
      final tensor = await worker.prepareRegion(
        const DetectRegion(40, 30, 160, 120),
      );
      expect(tensor, isNotNull);
      expect(tensor!.length, 3 * modelInputSize * modelInputSize);
    });

    test('the burst keeps the sharpest frame, not the last one', () async {
      final worker = await DetectorWorker.spawn();
      addTearDown(worker.dispose);

      await worker.beginBurst();
      // Flat grey scores near zero; the checkerboard is all edges. Offered
      // sharp-then-flat, so "keeps the last" and "keeps the sharpest" give
      // different answers.
      await worker.offerBurstFrameForTest(
        planes: _checkerPlanes(64, 48),
        width: 64,
        height: 48,
        sensorOrientation: 0,
      );
      await worker.offerBurstFrameForTest(
        planes: _bgraPlanes(64, 48),
        width: 64,
        height: 48,
        sensorOrientation: 0,
      );

      final prep = await worker.burstTensor();
      expect(prep, isNotNull);

      // The kept frame is the one with detail in it: a flat frame's tensor is
      // a single repeated value.
      final distinct = prep!.tensor.toSet().length;
      expect(distinct, greaterThan(1));
    });

    test('a burst with no frames offered yields nothing to send', () async {
      final worker = await DetectorWorker.spawn();
      addTearDown(worker.dispose);

      await worker.beginBurst();
      expect(await worker.burstTensor(), isNull);
    });

    test('a region asked for before any frame is a miss, not a hang', () async {
      final worker = await DetectorWorker.spawn();
      addTearDown(worker.dispose);

      expect(
        await worker.prepareRegion(const DetectRegion(0, 0, 10, 10)),
        isNull,
      );
    });
  });

  test('planes decode to an image of the requested size', () {
    final frame = decodePlanes(
      planes: _bgraPlanes(64, 48),
      width: 64,
      height: 48,
      sensorOrientation: 0,
    );

    expect(frame, isNotNull);
    expect(frame!.width, 64);
    expect(frame.height, 48);
  });

  test('a large frame is sampled down to the detector budget', () {
    final frame = decodePlanes(
      planes: _bgraPlanes(1920, 1080),
      width: 1920,
      height: 1080,
      sensorOrientation: 0,
      maxSide: 256,
    );

    // The model sees 224 square; carrying more pixels than that through the
    // conversion is the most expensive step in the tick.
    expect(frame!.width, 256);
    expect(frame.height, 144);
  });

  test('orientation is applied during the decode, not after it', () {
    final upright = decodePlanes(
      planes: _bgraPlanes(64, 48),
      width: 64,
      height: 48,
      sensorOrientation: 90,
    );

    // A quarter turn swaps the axes. Doing it here means no caller ever
    // holds a frame in the wrong frame of reference.
    expect(upright!.width, 48);
    expect(upright.height, 64);
  });

  test('the whole-frame tensor is the shape the model takes', () {
    final frame = decodePlanes(
      planes: _bgraPlanes(320, 240),
      width: 320,
      height: 240,
      sensorOrientation: 0,
    )!;

    final tensor = prepareInput(frame, wholeFrame(frame.width, frame.height));

    expect(tensor, isA<Float32List>());
    expect(tensor.length, 3 * modelInputSize * modelInputSize);
    expect(tensor.every((v) => v.isFinite), isTrue);
  });

  test('a region tensor is the same shape as a whole-frame one', () {
    final frame = decodePlanes(
      planes: _bgraPlanes(320, 240),
      width: 320,
      height: 240,
      sensorOrientation: 0,
    )!;

    // Stage two cuts a crop out of the frame the worker still holds; the
    // model cannot tell the two apart.
    final region = const DetectRegion(40, 30, 160, 120);
    expect(
      prepareInput(frame, region).length,
      3 * modelInputSize * modelInputSize,
    );
  });

  test('empty planes are a miss, not a crash', () {
    expect(
      decodePlanes(
        planes: const <FramePlane>[],
        width: 64,
        height: 48,
        sensorOrientation: 0,
      ),
      isNull,
    );
  });
}
