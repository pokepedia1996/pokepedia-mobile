/// The bundled corner-detection model, and the two-stage detection built on
/// it. Ports the runtime half of `features/scanner/utils/card-detector.ts`.
///
/// The model ships in the app rather than being fetched: web serves it with
/// `immutable, max-age=86400` and no content hash, so a browser can hold a
/// stale copy for a day after a rotation. Bundling sidesteps that and costs
/// the app its own update path — a model change rides an app release.
///
/// LiteRT rather than ONNX Runtime. `onnxruntime` ships no `Package.swift`,
/// and Swift Package Manager is becoming the default for Flutter's iOS
/// builds — the warning it printed says so itself. `tflite_flutter`, the
/// obvious replacement, has the same gap (tensorflow/flutter-tflite#303);
/// `flutter_litert` declares the TensorFlowLite frameworks as SPM binary
/// targets, so it is the one that actually settles the question.
///
/// The converted model keeps the ONNX one's signature exactly — `image`
/// `[1, 3, 224, 224]` float32 in, `prediction` `[1, 9]` float32 out, still
/// NCHW — so every line of preprocessing in `card_detector.dart` and every
/// line of decoding after it is untouched by the swap.
library;

import 'package:flutter/foundation.dart';
// `show`, not a bare import: the package exports a `Detection` of its own,
// which collides with this feature's.
import 'package:flutter_litert/flutter_litert.dart'
    show Interpreter, IsolateInterpreter;
import 'package:image/image.dart' as img;
import 'card_detector.dart';

const _modelAsset = 'assets/models/card_corners.tflite';

/// Eight corner coordinates, then the presence logit.
const _outputCount = 9;

/// A detection hung on the runtime must not wedge the tick loop.
const _inferenceTimeout = Duration(seconds: 2);

class CornerModel {
  CornerModel._(this._interpreter, this._isolate);

  /// Held only to own the native interpreter: [IsolateInterpreter] works from
  /// its address, so this must outlive it and be closed after it.
  final Interpreter _interpreter;

  /// Inference runs on its own isolate. A 6 MB model invoked on the platform
  /// thread would stall the frame it was called from, and this one is called
  /// from a camera tick.
  final IsolateInterpreter _isolate;

  static CornerModel? _instance;
  static Future<CornerModel>? _loading;

  /// Loads the model once per process.
  ///
  /// ~6 MB to parse, so this is deliberately not done lazily on the first
  /// tick — the scanner page warms it while the camera is initialising.
  static Future<CornerModel> load() {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    return _loading ??= _load();
  }

  static Future<CornerModel> _load() async {
    final interpreter = await Interpreter.fromAsset(_modelAsset);
    final isolate = await IsolateInterpreter.create(
      address: interpreter.address,
    );
    final model = CornerModel._(interpreter, isolate);
    await model._warm();
    _instance = model;
    return model;
  }

  /// One inference on an empty tensor, before any real frame.
  ///
  /// Loading the model is not the same as running it: TFLite allocates and
  /// first-touches its kernels on the first run, and without this that cost
  /// lands on the first live tick — the moment the user has just pointed the
  /// camera at a card and is waiting to see the outline. Ports
  /// `warmCardDetector`, which exists on web for the same reason.
  ///
  /// The result is discarded and a failure is swallowed: this is a timing
  /// optimisation, and a scanner that refused to start because a dummy
  /// inference failed would be strictly worse than one that starts cold.
  Future<void> _warm() async {
    try {
      final blank = Float32List(3 * modelInputSize * modelInputSize);
      await run(blank, wholeFrame(modelInputSize, modelInputSize));
    } catch (e) {
      if (kDebugMode) debugPrint('[scan] model warmup failed: $e');
    }
  }

  /// Runs the model over [region] of [frame] and decodes the result.
  ///
  /// Convenience for callers that already hold the image — the scanner does
  /// not, because its frames live on [DetectorWorker]'s isolate. That path
  /// uses [run] with a tensor the worker has already built.
  Future<Detection?> detect(img.Image frame, DetectRegion region) =>
      run(prepareInput(frame, region), region);

  /// Runs the model over a tensor someone else prepared, and decodes the
  /// result into [region]'s coordinate space.
  ///
  /// Concurrent calls are safe: a capture's own detection can land in the
  /// same frame as a live tick, and [IsolateInterpreter] queues a run issued
  /// while another is in flight rather than dropping it or letting the two
  /// collide on one native interpreter.
  Future<Detection?> run(Float32List input, DetectRegion region) async {
    try {
      // Flat typed data, matching the input tensor's byte size exactly — the
      // runtime memcpies it straight in rather than walking a nested list.
      final output = Float32List(_outputCount);

      await _isolate.run(input, output).timeout(_inferenceTimeout);

      return decodePrediction(output.toList(), region);
    } catch (e) {
      if (kDebugMode) debugPrint('[scan] corner model failed: $e');
      return null;
    }
  }

  void dispose() {
    // The isolate first: it holds the same native interpreter by address, and
    // freeing that underneath a live worker crashes the process. `close()`
    // kills the isolate before its first await, so not awaiting it here is
    // safe — and this is called from a synchronous `dispose`.
    _isolate.close();
    _interpreter.close();
    if (identical(_instance, this)) {
      _instance = null;
      _loading = null;
    }
  }
}

/// One pass over the whole frame, then a tighter re-run around what it found.
///
/// Stage 2 exists because stage 1 sees the card as a small part of a wide
/// frame, and the model's precision is proportional to how much of its 224×224
/// input the card occupies. Re-running on a zoomed crop buys back that
/// precision — but only when it agrees with stage 1, hence the tighter gates.
/// Ports `detectCardTwoStage`.
Future<Detection?> detectCardTwoStage(
  CornerModel model,
  img.Image frame,
) async {
  final full = wholeFrame(frame.width, frame.height);
  final stage1 = await model.detect(frame, full);
  if (stage1 == null || !passesGates(stage1, full)) return null;

  final region = stage2Region(stage1.quad, frame.width, frame.height);
  final stage2 = await model.detect(frame, region);
  if (stage2 == null) return stage1;

  // Accepted only on the stricter bar: stage 2's input is already zoomed and
  // mostly frontal, so a large aspect error there is a wrong answer rather
  // than foreshortening. Anything short of that keeps stage 1, which already
  // passed its own gates.
  final refined = passesGates(
    stage2,
    region,
    aspectTolerance: stage2AspectTolerance,
  );
  return refined ? stage2 : stage1;
}
