/// The bundled corner-detection model, and the two-stage detection built on
/// it. Ports the runtime half of `features/scanner/utils/card-detector.ts`.
///
/// The model ships in the app rather than being fetched: web serves it with
/// `immutable, max-age=86400` and no content hash, so a browser can hold a
/// stale copy for a day after a rotation. Bundling sidesteps that and costs
/// the app its own update path — a model change rides an app release.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'card_detector.dart';

const _modelAsset = 'assets/models/card_corners.onnx';
const _inputName = 'image';
const _outputName = 'prediction';

/// A detection hung on the runtime must not wedge the tick loop.
const _inferenceTimeout = Duration(seconds: 2);

class CornerModel {
  CornerModel._(this._session);

  final OrtSession _session;

  /// Serialises inference. The tick loop is single-flight already, but a
  /// capture's own detection can land in the same frame as a live tick, and
  /// two concurrent `run` calls on one session is not a supported shape.
  Future<void> _chain = Future.value();

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
    OrtEnv.instance.init();
    final bytes = await rootBundle.load(_modelAsset);
    final session = OrtSession.fromBuffer(
      bytes.buffer.asUint8List(),
      OrtSessionOptions(),
    );
    final model = CornerModel._(session);
    _instance = model;
    return model;
  }

  /// Runs the model over [region] of [frame] and decodes the result.
  Future<Detection?> detect(img.Image frame, DetectRegion region) {
    final run = _chain.then((_) => _detect(frame, region));
    // The chain must survive a failure, or one bad frame stalls every tick
    // after it.
    _chain = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<Detection?> _detect(img.Image frame, DetectRegion region) async {
    OrtValueTensor? input;
    List<OrtValue?>? outputs;
    try {
      final tensor = prepareInput(frame, region);
      input = OrtValueTensor.createTensorWithDataList(tensor, [
        1,
        3,
        modelInputSize,
        modelInputSize,
      ]);

      outputs = await _session
          .runAsync(OrtRunOptions(), {_inputName: input}, [_outputName])
          ?.timeout(_inferenceTimeout);

      final raw = outputs?.firstOrNull?.value;
      final prediction = _flatten(raw);
      if (prediction == null || prediction.length < 9) return null;
      return decodePrediction(prediction, region);
    } catch (e) {
      if (kDebugMode) debugPrint('[scan] corner model failed: $e');
      return null;
    } finally {
      input?.release();
      for (final o in outputs ?? const <OrtValue?>[]) {
        o?.release();
      }
    }
  }

  /// The runtime hands back the output nested by shape; the model's is
  /// `[1, 9]`, but tolerate a bare list too rather than assuming.
  List<double>? _flatten(Object? raw) {
    if (raw is List && raw.isNotEmpty && raw.first is List) {
      return (raw.first as List).map((v) => (v as num).toDouble()).toList();
    }
    if (raw is List) {
      return raw.whereType<num>().map((v) => v.toDouble()).toList();
    }
    if (raw is Float32List) return raw.toList();
    return null;
  }

  void dispose() {
    _session.release();
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
