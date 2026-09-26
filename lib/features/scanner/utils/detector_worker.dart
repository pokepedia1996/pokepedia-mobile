import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'card_capture.dart';
import 'card_detector.dart';
import 'camera_frame.dart';
import 'warp_quad.dart';

/// The frame pipeline, on an isolate of its own.
///
/// Everything the scanner did per tick except the inference itself ran on the
/// UI isolate: a YUV420→RGB conversion over ~440k pixels, a full-image
/// rotate, two crop-and-resize passes, and 300k `getPixel` calls to build the
/// tensors. `package:image` is pure Dart with no SIMD, so that is tens of
/// milliseconds of blocked UI thread eight times a second — which is what the
/// camera preview stuttering actually was. The web scanner does the same
/// steps on the GPU through `drawImage`, which is why it feels smooth doing
/// no less work.
///
/// The worker keeps the decoded frame rather than handing it back, so the
/// second stage and the capture warp run against it without copying a
/// megabyte across the boundary each time. The UI isolate only ever sends
/// camera planes in and gets a handful of numbers out.
class DetectorWorker {
  DetectorWorker._(
    this._isolate,
    this._commands,
    this._responses,
    Stream<dynamic> replies,
  ) {
    _replies = replies.listen(_onResponse);
  }

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _responses;

  /// The one subscription to the port.
  ///
  /// A `ReceivePort` is a single-subscription stream, and the handshake that
  /// collects the worker's [SendPort] has already subscribed to it — so this
  /// listens to the broadcast view rather than the port again. Listening
  /// twice throws, the throw surfaced as a failed `spawn`, and a null worker
  /// made every tick return early: a scanner that saw nothing, ever.
  late final StreamSubscription<dynamic> _replies;

  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  var _closed = false;

  static Future<DetectorWorker> spawn() async {
    final responses = ReceivePort();
    final replies = responses.asBroadcastStream();

    final isolate = await Isolate.spawn(_entryPoint, responses.sendPort);
    final commands =
        await replies.firstWhere((message) => message is SendPort) as SendPort;

    return DetectorWorker._(isolate, commands, responses, replies);
  }

  void _onResponse(dynamic message) {
    if (message is! _Response) return;
    _pending.remove(message.id)?.complete(message.payload);
  }

  Future<Object?> _send(Object request) {
    if (_closed) return Future.value();
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands.send(_Request(id, request));
    return completer.future;
  }

  /// Decodes [frame], orients it, and returns the whole-frame tensor along
  /// with the size it was decoded at — which is all the UI needs to place the
  /// detection it gets back.
  Future<FramePrep?> prepareFrame(
    CameraImage frame,
    int sensorOrientation,
  ) async {
    // Planes are copied out here because `CameraImage` itself is not
    // sendable, and the camera reuses its buffers for the next frame.
    final result = await _send(
      _PrepareFrame(
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
        sensorOrientation: sensorOrientation,
      ),
    );
    return result as FramePrep?;
  }

  /// [prepareFrame] without a `CameraImage`, for tests.
  ///
  /// The planes are the only part of a frame that crosses the boundary, so
  /// this is the same call the scanner makes — it just skips constructing a
  /// camera object the test has no way to make.
  @visibleForTesting
  Future<FramePrep?> prepareFrameForTest({
    required List<FramePlane> planes,
    required int width,
    required int height,
    required int sensorOrientation,
  }) async {
    final result = await _send(
      _PrepareFrame(
        planes: planes,
        width: width,
        height: height,
        sensorOrientation: sensorOrientation,
      ),
    );
    return result as FramePrep?;
  }

  /// Starts a capture burst, forgetting whatever the last one kept.
  Future<void> beginBurst() => _send(const _BeginBurst()).then((_) {});

  /// Scores one burst candidate and keeps it if it is the sharpest so far.
  ///
  /// Web does the same in `captureBurstFrame`: two frames a short gap apart,
  /// keep the higher Laplacian variance. A hand holding a card is never
  /// still, and a single grab lands on the blurred half of that wobble often
  /// enough to matter.
  Future<void> offerBurstFrame(CameraImage frame, int sensorOrientation) async {
    await _send(
      _OfferBurstFrame(
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
        sensorOrientation: sensorOrientation,
      ),
    );
  }

  /// [offerBurstFrame] without a `CameraImage`, for tests.
  @visibleForTesting
  Future<void> offerBurstFrameForTest({
    required List<FramePlane> planes,
    required int width,
    required int height,
    required int sensorOrientation,
  }) async {
    await _send(
      _OfferBurstFrame(
        planes: planes,
        width: width,
        height: height,
        sensorOrientation: sensorOrientation,
      ),
    );
  }

  /// The sharpest burst frame, as a tensor to re-detect on.
  ///
  /// The cascade's first tier: web re-runs the detector on the frame it is
  /// actually about to send, not on the older one that happened to trip the
  /// lock.
  Future<FramePrep?> burstTensor() async {
    final result = await _send(const _BurstTensor());
    return result as FramePrep?;
  }

  /// Warps [quad] out of the sharpest burst frame.
  Future<CardCapture?> warpBurst(Quad quad) async {
    final result = await _send(_WarpBurst(quad));
    return result as CardCapture?;
  }

  /// The second stage's tensor, cut from the frame the worker still holds.
  Future<Float32List?> prepareRegion(DetectRegion region) async {
    final result = await _send(_PrepareRegion(region));
    return result as Float32List?;
  }

  /// Warps [quad] out of the retained frame — the capture, without sending
  /// the frame anywhere.
  Future<CardCapture?> warp(Quad quad) async {
    final result = await _send(_Warp(quad));
    return result as CardCapture?;
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete();
    }
    _pending.clear();
    await _replies.cancel();
    _responses.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

/// What [DetectorWorker.prepareFrame] answers with.
class FramePrep {
  const FramePrep({
    required this.tensor,
    required this.region,
    required this.width,
    required this.height,
  });

  final Float32List tensor;

  /// The part of the frame [tensor] was cut from.
  ///
  /// Returned rather than recomputed by the caller: the prediction's corners
  /// are fractions *of this rect*, so decoding them against any other one
  /// puts the quad somewhere the card is not.
  final DetectRegion region;

  /// The decoded frame's size, after orientation — the space the detection's
  /// corners come back in.
  final int width;
  final int height;
}

// --- messages ---------------------------------------------------------

class _Request {
  const _Request(this.id, this.payload);
  final int id;
  final Object payload;
}

class _Response {
  const _Response(this.id, this.payload);
  final int id;
  final Object? payload;
}

typedef _Plane = FramePlane;

class _PrepareFrame {
  const _PrepareFrame({
    required this.planes,
    required this.width,
    required this.height,
    required this.sensorOrientation,
  });

  final List<_Plane> planes;
  final int width;
  final int height;
  final int sensorOrientation;
}

class _PrepareRegion {
  const _PrepareRegion(this.region);
  final DetectRegion region;
}

class _BeginBurst {
  const _BeginBurst();
}

class _OfferBurstFrame {
  const _OfferBurstFrame({
    required this.planes,
    required this.width,
    required this.height,
    required this.sensorOrientation,
  });

  final List<_Plane> planes;
  final int width;
  final int height;
  final int sensorOrientation;
}

class _BurstTensor {
  const _BurstTensor();
}

class _WarpBurst {
  const _WarpBurst(this.quad);
  final Quad quad;
}

class _Warp {
  const _Warp(this.quad);
  final Quad quad;
}

// --- the isolate ------------------------------------------------------

void _entryPoint(SendPort responses) {
  final commands = ReceivePort();
  responses.send(commands.sendPort);

  // The frame the last `prepareFrame` decoded. Stage two and the capture
  // warp both read it, which is the whole reason it stays here.
  img.Image? frame;

  // The sharpest frame of the current capture burst, and its score.
  img.Image? best;
  var bestScore = -1.0;

  commands.listen((message) {
    if (message is! _Request) return;
    Object? payload;
    try {
      final request = message.payload;
      if (request is _PrepareFrame) {
        final decoded = decodePlanes(
          planes: request.planes,
          width: request.width,
          height: request.height,
          sensorOrientation: request.sensorOrientation,
        );
        frame = decoded;
        if (decoded != null) {
          // The whole frame. Cropping to the visible preview rect matched
          // what web does, but it cost sensitivity here: the truncation gate
          // then rejects a card whose edges run past the crop, which is
          // exactly how someone fills the viewfinder. Web's canvas genuinely
          // is the visible rect; this frame's relationship to the preview
          // box is not confirmed, and a wrong crop loses the card outright.
          final region = wholeFrame(decoded.width, decoded.height);
          if (kDebugMode) {
            debugPrint('[scan] frame ${decoded.width}x${decoded.height}');
          }
          payload = FramePrep(
            tensor: prepareInput(decoded, region),
            region: region,
            width: decoded.width,
            height: decoded.height,
          );
        }
      } else if (request is _BeginBurst) {
        best = null;
        bestScore = -1;
      } else if (request is _OfferBurstFrame) {
        final decoded = decodePlanes(
          planes: request.planes,
          width: request.width,
          height: request.height,
          sensorOrientation: request.sensorOrientation,
        );
        if (decoded != null) {
          final score = scoreFrame(decoded).variance;
          if (score > bestScore) {
            bestScore = score;
            best = decoded;
          }
        }
      } else if (request is _BurstTensor) {
        final held = best;
        if (held != null) {
          final region = wholeFrame(held.width, held.height);
          // The burst frame becomes the frame: stage two and the warp must
          // read the one being sent, not the older tick frame.
          frame = held;
          payload = FramePrep(
            tensor: prepareInput(held, region),
            region: region,
            width: held.width,
            height: held.height,
          );
        }
      } else if (request is _WarpBurst) {
        final held = best;
        if (held != null) payload = captureFromQuad(held, request.quad);
      } else if (request is _PrepareRegion) {
        final held = frame;
        if (held != null) payload = prepareInput(held, request.region);
      } else if (request is _Warp) {
        final held = frame;
        if (held != null) payload = captureFromQuad(held, request.quad);
      }
    } catch (e) {
      // One bad frame must not take the worker down with it — the tick
      // simply finds nothing and the next frame tries again.
      if (kDebugMode) debugPrint('[scan] worker failed: $e');
      payload = null;
    }
    responses.send(_Response(message.id, payload));
  });
}
