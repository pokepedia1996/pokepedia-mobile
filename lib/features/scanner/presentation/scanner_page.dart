import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../repository/models/scan_models.dart';
import '../repository/scanner_repository.dart';
import '../usecase/scan_session_notifier.dart';
import '../usecase/scanner_notifier.dart';
import '../usecase/scan_sound.dart';
import '../utils/auto_capture.dart';
import '../utils/card_detector.dart';
import '../utils/detector_worker.dart';
import '../utils/card_capture.dart';
import '../utils/corner_model.dart';
import '../utils/warp_quad.dart';
import 'widgets/scan_hint.dart';
import 'widgets/scan_result_sheet.dart';
import 'widgets/scan_session_sheet.dart';
import 'widgets/scan_price_burst.dart';
import 'widgets/scan_status_pill.dart';
import 'widgets/scanner_top_bar.dart';

/// Ports `features/scanner/components/ScannerView.tsx`.
///
/// ## What's the same, and what deliberately isn't
///
/// Like the web, a corner-detection model runs over the live feed and capture
/// fires automatically once a detected quad holds still — there is no shutter.
/// The same bundled `.tflite` weights, the same gates and lock timing, the
/// same endpoint, the same batch semantics, the same two terminal actions.
/// What differs is plumbing: frames are decoded and tensors built on
/// [DetectorWorker]'s isolate, and inference runs on [CornerModel]'s.
///
/// The pieces of ScannerView that stop a fast scanning run from corrupting
/// itself are carried over verbatim:
///
///  * a **generation guard** (in `ScannerNotifier`) so a slow earlier response
///    can't overwrite a newer scan's result;
///  * a **single-flight gate** so two locks can't put two captures in
///    flight against one card;
///  * a **settle delay** after each result, long enough to read the price
///    before the next capture is allowed.
class ScannerPage extends ConsumerStatefulWidget {
  const ScannerPage({super.key});

  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends ConsumerState<ScannerPage>
    with WidgetsBindingObserver {
  /// How long a result stays up before the shutter re-arms. Ports
  /// `SCAN_RESULT_SETTLE_MS`.
  static const _resultSettle = Duration(milliseconds: 900);

  /// How often the detector samples the stream. Ports the web's poll rate.
  static const _tickInterval = Duration(milliseconds: 120);

  /// Web's `CAPTURE_BURST_FRAMES` / `CAPTURE_BURST_GAP_MS`.
  /// Past this, the quad that locked the overlay is too old to stand in for
  /// a fresh detection — well over the burst window it normally crosses, so
  /// this is a backstop rather than a limit anything reaches. Ports
  /// `STALE_QUAD_MAX_AGE_MS`.
  static const _staleQuadMaxAge = Duration(milliseconds: 1500);

  static const _burstFrames = 2;
  static const _burstGap = Duration(milliseconds: 80);

  /// Up to 40% of [_resultSettle] added at random on each re-arm.
  ///
  /// Not cosmetic: the scan tier is 30 requests per 60s per user, and the
  /// embedder sheds load above ~32 concurrent requests. Without jitter a room
  /// of phones scanning at a natural pace re-arms in lockstep and arrives in
  /// waves, tripping that shedding far earlier than the same total volume
  /// spread out would. Ports the web's own capture jitter.
  static const _rearmJitterFraction = 0.4;

  final _jitter = math.Random();

  /// The corner model, warmed while the camera starts.
  CornerModel? _model;

  /// Owns the decoded frame and every per-pixel step of a tick. Spawned
  /// alongside the model, because both are dead weight until the camera is
  /// actually running.
  DetectorWorker? _worker;

  /// Newest frame off the stream. Held, not queued: detection is slower than
  /// frames arrive, and a queue would work through stale poses instead of
  /// looking at what the camera sees now.
  CameraImage? _latestFrame;

  bool _detecting = false;
  Timer? _tickTimer;
  final _autoCapture = AutoCaptureMachine();

  /// The card the last accepted capture filed.
  ///
  /// Web's `lastCapturedCardIdRef`: what the duplicate prompt compares
  /// against. Cleared whenever the scanner returns to idle, so the question
  /// is only ever asked about the card immediately before this one.
  int? _lastCapturedCardId;

  /// The card the price burst is showing, and the timer that clears it.
  ///
  /// Separate from [_activeTempId], which drives the result sheet and stays
  /// up until the next scan: the burst is a moment, not a state.
  int? _burstCardId;
  Timer? _burstTimer;

  /// How long the big price stays up. Web's `PRICE_BURST_VISIBLE_MS` — long
  /// enough to read at arm's length, short enough not to sit over the next
  /// card.
  static const _burstVisible = Duration(milliseconds: 2200);

  /// How long the opening hint stays up. Web's `HINT_VISIBLE_MS`.
  static const _hintVisibleFor = Duration(milliseconds: 3000);

  /// What the status pill reflects.
  bool _cardDetected = false;
  bool _locking = false;

  /// The opening "Arahkan kamera ke kartu" hint. Goes after
  /// [_hintVisibleFor] or the first capture, whichever is sooner, and does
  /// not come back.
  var _hintVisible = true;
  Timer? _hintTimer;

  /// The top bar's pause. Stops detection without stopping the camera, so
  /// the user can reposition a binder without it firing on every page.
  var _paused = false;

  CameraController? _controller;
  Future<void>? _initialization;
  String? _cameraError;

  /// True from the shutter press until the crop is encoded — before
  /// `ScanLoading` exists, so this is what blocks a double-tap.
  var _capturing = false;

  var _torchOn = false;
  var _torchSupported = true;
  var _sessionOpen = false;
  Timer? _rearmTimer;

  /// Which session row the result sheet is showing.
  String? _activeTempId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialization = _startCamera();
    DetectorWorker.spawn()
        .then((worker) {
          if (mounted) {
            _worker = worker;
          } else {
            worker.dispose();
          }
        })
        .catchError((Object e) {
          debugPrint('[scan] worker spawn failed: $e');
          // Said out loud. Without the worker the tick returns early on
          // every frame, so the scanner is alive, streaming, and incapable
          // of ever detecting anything — which looks like a camera that
          // cannot see rather than a fault.
          if (mounted) {
            setState(() {
              _cameraError = 'Pemindai gagal disiapkan. Tutup dan buka lagi.';
            });
          }
        });
    // ~6 MB to parse; the camera's own startup is dead time anyway.
    CornerModel.load()
        .then((model) {
          if (mounted) {
            _model = model;
          } else {
            model.dispose();
          }
        })
        .catchError((Object e) {
          debugPrint('[scan] model load failed: $e');
          // Same reasoning as the worker: without the model `_tick` returns
          // early forever, and a scanner that streams but never detects
          // reads as a camera problem rather than the fault it is.
          if (mounted) {
            setState(() {
              _cameraError = 'Pemindai gagal disiapkan. Tutup dan buka lagi.';
            });
          }
        });
  }

  @override
  void dispose() {
    _worker?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _rearmTimer?.cancel();
    _burstTimer?.cancel();
    _hintTimer?.cancel();
    _tickTimer?.cancel();
    final controller = _controller;
    if (controller != null) {
      unawaited(
        controller
            .stopImageStream()
            .catchError((_) {})
            .whenComplete(controller.dispose),
      );
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    // Android reclaims the camera when the app leaves the foreground; holding
    // a dead controller across resume shows a frozen last frame forever.
    if (lifecycleState == AppLifecycleState.inactive) {
      _controller = null;
      // Stop the tick first, or it runs against a camera that no longer
      // exists; and stop the stream before disposing, or Android keeps
      // delivering frames to a dead listener.
      _tickTimer?.cancel();
      _tickTimer = null;
      _latestFrame = null;
      _autoCapture.reset();
      unawaited(
        controller
            .stopImageStream()
            .catchError((_) {})
            .whenComplete(controller.dispose),
      );
      if (mounted) {
        setState(() {
          _cardDetected = false;
          _locking = false;
        });
      }
    } else if (lifecycleState == AppLifecycleState.resumed) {
      setState(() => _initialization = _startCamera());
    }
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'Kamera tidak tersedia');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        // `veryHigh` (~1080p) rather than `max`: the server downscales to a
        // 1000px working side regardless, so a larger still would only cost
        // decode time and memory on the isolate for detail the embedder
        // immediately discards.
        ResolutionPreset.veryHigh,
        enableAudio: false,
        // Streaming formats, not `jpeg` — `startImageStream` delivers YUV420
        // on Android and BGRA on iOS.
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      // Locked so the guide box and the still stay in the same coordinate
      // space — a rotation between framing and capture would offset every crop.
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      // Pinned to 1x. A device that restores a previous zoom frames the card
      // differently from the guide box the crop is measured against, and
      // digital zoom softens exactly the printed detail the embedder reads.
      // Best-effort: a camera that refuses is still usable as it opened.
      try {
        await controller.setZoomLevel(1);
      } on CameraException {
        // Left at the device default.
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraError = null;
      });
      _hintTimer ??= Timer(_hintVisibleFor, () {
        if (mounted) setState(() => _hintVisible = false);
      });
      await _startDetection(controller);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = e.code == 'CameraAccessDenied'
            ? 'Izin kamera ditolak. Aktifkan di pengaturan aplikasi.'
            : 'Kamera gagal dimulai (${e.code})';
      });
    }
  }

  /// The guide box in screen coordinates, at exactly [cardAspect].
  /// Frames stream in; a timer samples the newest one every
  /// [_tickInterval].
  ///
  /// Separate stream and tick on purpose: frames arrive at 30fps and
  /// detection cannot keep up, so sampling on a timer keeps the cadence
  /// predictable and always works on the most recent pose.
  Future<void> _startDetection(CameraController controller) async {
    try {
      await controller.startImageStream((frame) => _latestFrame = frame);
    } on CameraException catch (e) {
      debugPrint('[scan] image stream failed: $e');
      return;
    }
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  /// Clockwise turns that bring a streamed frame upright.
  ///
  /// Android streams in sensor orientation, so the sensor's mounting angle is
  /// the rotation. iOS does not: `lockCaptureOrientation` sets the video
  /// output connection to portrait, so AVFoundation hands over buffers that
  /// are already upright — while `camera_avfoundation` still reports a
  /// hardcoded `sensorOrientation` of 90. Rotating by it turned every iOS
  /// frame sideways, far past the ±30° the corner model was trained on, so
  /// nothing ever passed the gates and no scan was ever sent.
  int _frameRotation(CameraController controller) =>
      Platform.isIOS ? 0 : controller.description.sensorOrientation;

  Future<void> _tick() async {
    if (!mounted || _detecting || _capturing || _paused) return;
    final model = _model;
    final frame = _latestFrame;
    final controller = _controller;
    if (model == null || frame == null || controller == null) return;
    if (ref.read(scannerProvider) is ScanLoading) return;

    _detecting = true;
    try {
      // Decode, orient and build the first tensor on the worker's isolate.
      // This is the pixel work that used to block the UI thread every tick.
      final prep = await _worker?.prepareFrame(
        frame,
        _frameRotation(controller),
      );
      if (prep == null || !mounted) return;

      // Coarse only: the second stage is for the frame about to be sent,
      // not for tracking. See [_detectCoarse].
      final detection = await _detectCoarse(model, prep);
      if (!mounted) return;

      final result = _autoCapture.tick(detection?.quad, DateTime.now());
      final detected = result.quad != null;
      final locking = result.progress > 0 && result.progress < 1;
      if (detected != _cardDetected || locking != _locking) {
        setState(() {
          _cardDetected = detected;
          _locking = locking;
        });
      }

      if (result.action == AutoCaptureAction.capture && result.quad != null) {
        await _captureQuad(
          model,
          liveQuad: result.quad!,
          liveQuadAt: DateTime.now(),
          presence: detection?.present ?? 0,
        );
      }
    } finally {
      _detecting = false;
    }
  }

  /// Stage one alone — what the live loop tracks with.
  ///
  /// Two reasons the tick does not refine, both web's (`detectCardCoarse`).
  /// The refined quad and the coarse one disagree by a few pixels every
  /// tick, and that disagreement is movement as far as the lock's drift
  /// check is concerned: the stability timer restarts on a card that is
  /// being held perfectly still, and the lock never fires. And the second
  /// stage costs another crop, another resize, another 150k pixel reads and
  /// another inference — per tick, eight times a second, for a quad that is
  /// only ever drawn as an outline. Precision is what capture needs, and
  /// capture re-runs the full two-stage detector on its own frame.
  Future<Detection?> _detectCoarse(CornerModel model, FramePrep prep) async {
    final detection = await model.run(prep.tensor, prep.region);
    if (detection == null || !passesGates(detection, prep.region)) return null;
    return detection;
  }

  /// One pass over the whole frame, then a tighter re-run around what it
  /// found — `detectCardTwoStage`, split so each tensor is built on the
  /// worker while the model runs on its own isolate.
  Future<Detection?> _detect(CornerModel model, FramePrep prep) async {
    // The rect the worker actually cut the tensor from — the visible crop,
    // not the whole sensor frame. Recomputing it here instead of taking it
    // back would risk the two disagreeing, and the corners are fractions of
    // whichever rect the tensor came from.
    final full = prep.region;
    final stage1 = await model.run(prep.tensor, full);
    if (stage1 == null || !passesGates(stage1, full)) return null;

    final region = stage2Region(stage1.quad, prep.width, prep.height);
    // Only now is the second tensor cut. Building it before the gates had
    // passed was half the tick's preprocessing spent on frames that were
    // never going to refine.
    final tensor = await _worker?.prepareRegion(region);
    if (tensor == null) return stage1;

    final stage2 = await model.run(tensor, region);
    if (stage2 == null) return stage1;

    // Accepted only on the stricter bar: stage 2's input is already zoomed
    // and mostly frontal, so a large aspect error there is a wrong answer
    // rather than foreshortening.
    return passesGates(stage2, region, aspectTolerance: stage2AspectTolerance)
        ? stage2
        : stage1;
  }

  /// Warps the locked quad out of the frame it was detected in and scans it.
  ///
  /// The same frame detection ran on, not a fresh still: the quad's
  /// coordinates only mean anything there, and a `takePicture` between lock
  /// and capture would move the card out from under them.
  /// Captures, then finds the card in what it captured — web's crop cascade.
  ///
  /// The quad that tripped the lock came from an older frame. Warping the
  /// new capture with it assumes the card has not moved in the meantime,
  /// which is exactly the assumption a hand holding a card breaks. So the
  /// detector runs again on the frame about to be sent, and the live quad is
  /// only the fallback.
  ///
  /// A miss is a miss: if no tier finds a card, nothing is sent. An unwarped
  /// frame reaches the embedder as a photo of a desk with a card on it, and
  /// scores against the catalog accordingly.
  Future<void> _captureQuad(
    CornerModel model, {
    required Quad liveQuad,
    required DateTime liveQuadAt,
    required double presence,
  }) async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _hintVisible = false;
    });
    _rearmTimer?.cancel();

    try {
      final worker = _worker;
      final controller = _controller;
      if (worker == null || controller == null) return;

      final orientation = _frameRotation(controller);

      // The burst: two frames a gap apart, sharpest kept. A hand is never
      // still, and one grab lands on the blurred half of that wobble often
      // enough to be the difference between a match and a miss.
      await worker.beginBurst();
      for (var i = 0; i < _burstFrames; i++) {
        final frame = _latestFrame;
        if (frame == null || !mounted) return;
        await worker.offerBurstFrame(frame, orientation);
        if (i < _burstFrames - 1) await Future<void>.delayed(_burstGap);
      }
      if (!mounted) return;

      final prep = await worker.burstTensor();
      if (prep == null || !mounted) return;

      // Tier one: detect on the frame being sent.
      var quad = (await _detect(model, prep))?.quad;
      var tier = 'model';
      var tierPresence = presence;

      // Tier two: the quad that locked the overlay, if it still describes a
      // card-shaped thing inside this frame. Aspect alone cannot vouch for
      // it — it is a copy of a quad that already passed — so bounds are what
      // this tier actually checks.
      if (quad == null &&
          DateTime.now().difference(liveQuadAt) <= _staleQuadMaxAge &&
          _quadWithinFrame(liveQuad, prep) &&
          passesGates(
            Detection(present: presence, quad: liveQuad),
            prep.region,
          )) {
        quad = liveQuad;
        tier = 'model_stale_quad';
      }

      if (quad == null) {
        // Web's miss branch: re-arm and say so rather than sending anything.
        _showError('Kartu tidak terdeteksi, posisikan ulang');
        _autoCapture.reset();
        return;
      }

      final capture = await worker.warpBurst(quad);
      if (capture == null || !mounted) return;

      final result = await ref
          .read(scannerProvider.notifier)
          .scan(
            capture: capture,
            language: ref.read(scanLanguageProvider),
            captureMeta: _quadCaptureMeta(
              prep.width,
              prep.height,
              capture,
              quad,
              tierPresence,
              tier,
            ),
          );
      if (!mounted) return;

      if (result is ScanMatched) {
        // The same card twice in a row is usually the scanner having fired
        // again on a card still in shot, not someone holding two copies. It
        // is a real case though — playsets are four of one card — so it is a
        // question rather than a refusal, and the answer is theirs.
        if (result.card.id == _lastCapturedCardId) {
          final again = await _confirmDuplicate(result.card);
          if (!mounted || !again) {
            // Declined: nothing is added, and the machine is left as the
            // fire put it — suspended until the card moves or leaves. A
            // `reset()` here would re-arm on the card still sitting in shot
            // and ask the same question again a second later.
            return;
          }
        }
        _addMatch(result);
      } else if (result is ScanFailed) {
        _showError(result.message);
        // Let the same card be retried without moving it.
        _autoCapture.reset();
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
      _scheduleRearm();
    }
  }

  /// Files a match into the session and says so.
  void _addMatch(ScanMatched result) {
    final tempId = ref
        .read(scanSessionProvider.notifier)
        .addItem(
          card: result.card,
          variants: result.variants,
          needsReview: !result.confident,
          logId: result.logId,
        );
    setState(() {
      _activeTempId = tempId;
      _lastCapturedCardId = result.card.id;
      _burstCardId = result.card.id;
    });
    _burstTimer?.cancel();
    _burstTimer = Timer(_burstVisible, () {
      if (mounted) setState(() => _burstCardId = null);
    });
    // Fired once per card that actually lands, matching web. With no
    // shutter this is the only confirmation the user gets — they are
    // looking at the card in their hand, not the screen.
    unawaited(ref.read(scanSoundProvider).play());
  }

  /// "Kartu yang sama terdeteksi" — web's duplicate prompt.
  ///
  /// Asked before the copy is filed rather than offered as an undo
  /// afterwards: the session merges duplicates by quantity, so an unwanted
  /// second copy is not a row to delete but a number to correct.
  Future<bool> _confirmDuplicate(ScanCard card) async {
    var again = false;
    await showConfirmDialog(
      context,
      title: 'Kartu yang sama terdeteksi',
      // Web falls back to "Kartu ini" when the row carries no name, and the
      // column is nullable here too.
      description:
          '${card.nameId?.trim().isNotEmpty == true ? card.nameId : "Kartu ini"}'
          ' baru saja dipindai. Tambahkan lagi?',
      confirmLabel: 'Tambahkan',
      cancelLabel: 'Batalkan',
      // Adding a card is not a destructive act, whatever the default is.
      destructive: false,
      onConfirm: () async => again = true,
    );
    return again;
  }

  /// Whether [quad] still lands inside [prep]'s frame, with web's 10% slack.
  bool _quadWithinFrame(Quad quad, FramePrep prep) {
    final slackX = prep.width * 0.1;
    final slackY = prep.height * 0.1;
    return quad.corners.every(
      (p) =>
          p.x >= -slackX &&
          p.x <= prep.width + slackX &&
          p.y >= -slackY &&
          p.y <= prep.height + slackY,
    );
  }

  Map<String, dynamic> _quadCaptureMeta(
    int frameWidth,
    int frameHeight,
    CardCapture capture,
    Quad quad,
    double presence,
    String cropTier,
  ) {
    final controller = _controller;
    final bounds = quad.bounds;
    return {
      'label': controller?.description.name ?? '',
      'deviceId': controller?.description.name ?? '',
      'trackWidth': frameWidth,
      'trackHeight': frameHeight,
      'pinnedToSingleLens': true,
      'videoWidth': frameWidth,
      'videoHeight': frameHeight,
      'cropWidth': (bounds.right - bounds.left).round().clamp(0, 20000),
      'cropHeight': (bounds.bottom - bounds.top).round().clamp(0, 20000),
      'outWidth': capture.width,
      'outHeight': capture.height,
      'sharpness': capture.sharpness.round().clamp(0, 1000000),
      'luma': capture.luma.round().clamp(0, 255),
      'cropTier': cropTier,
      'modelPresence': presence.clamp(0.0, 1.0),
    };
  }

  /// Returns the scanner to idle once the result has had a moment to register,
  /// so the status pill and shutter reflect "ready" again.
  void _scheduleRearm({Duration? after}) {
    _rearmTimer?.cancel();
    final base = after ?? _resultSettle;
    final delay =
        base +
        Duration(
          milliseconds:
              (base.inMilliseconds *
                      _rearmJitterFraction *
                      _jitter.nextDouble())
                  .round(),
        );
    _rearmTimer = Timer(delay, () {
      if (mounted) ref.read(scannerProvider.notifier).reset();
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
    } on CameraException {
      // Plenty of devices report a camera but no torch; stop offering it
      // rather than surfacing an error the user can do nothing about.
      if (mounted) setState(() => _torchSupported = false);
    }
  }

  void _onLanguageChanged(CardLanguage language) {
    ref.read(scanLanguageProvider.notifier).set(language);
    // A result tagged with the old language shouldn't stay on screen implying
    // it was scanned under the new one.
    _rearmTimer?.cancel();
    ref.read(scannerProvider.notifier).reset();
    setState(() {
      _activeTempId = null;
      // Web clears this here and only here — not on the per-scan re-arm,
      // which would wipe it 900ms after every capture and leave the
      // duplicate prompt with nothing to compare against.
      _lastCapturedCardId = null;
    });
  }

  /// Applies a variant-strip pick and reports the correction back against this
  /// scan's `recognition_logs` row. Ports `useConfirmScanChoice`.
  void _selectVariant(ScanSessionItem item, ScanCard card) {
    ref
        .read(scanSessionProvider.notifier)
        .setCard(
          item.tempId,
          card,
          item.variants.isNotEmpty ? item.variants : [item.card],
        );
    final logId = item.logId;
    if (logId != null) {
      unawaited(
        ref
            .read(scannerRepositoryProvider)
            .confirmChoice(logId: logId, chosenCardId: card.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scannerProvider);
    final session = ref.watch(scanSessionProvider);
    final language = ref.watch(scanLanguageProvider);

    final cameraReady =
        _cameraError == null && (_controller?.value.isInitialized ?? false);

    final activeItem = _activeTempId == null
        ? null
        : session.where((it) => it.tempId == _activeTempId).firstOrNull;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            fit: StackFit.expand,
            children: [
              _buildPreview(screenSize),
              ScanHint(
                visible: _hintVisible && cameraReady && scanState is ScanIdle,
              ),
              // Web shows the pill only while detection is live — not over
              // the session sheet, where nothing is being looked for.
              if (cameraReady && !_sessionOpen)
                Positioned(
                  // Web's `top-[9.5rem]`.
                  top: MediaQuery.of(context).padding.top + 152,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: ScanStatusPill(status: _pillStatus(scanState)),
                    ),
                  ),
                ),
              ScanPriceBurst(
                visible: _burstCardId != null,
                price: _burstCardId == null
                    ? null
                    : ref
                          .watch(scanSessionPricesProvider)
                          .valueOrNull?[_burstCardId]
                          ?.price,
              ),
              ScannerTopBar(
                language: language,
                onLanguageChanged: _onLanguageChanged,
                busy: _capturing || scanState is ScanLoading,
                paused: _paused,
                onTogglePause: _togglePause,
                torchSupported: _torchSupported,
                torchOn: _torchOn,
                onToggleTorch: _toggleTorch,
                soundOn: !ref.watch(scanSoundProvider).muted,
                onToggleSound: _toggleSound,
                onClose: () => Navigator.of(context).maybePop(),
              ),
              ScanResultSheet(
                item: activeItem,
                onSelectVariant: (card) {
                  if (activeItem != null) _selectVariant(activeItem, card);
                },
                onOpenSession: () => setState(() => _sessionOpen = true),
              ),
              if (_sessionOpen)
                ScanSessionSheet(
                  onClose: () => setState(() => _sessionOpen = false),
                  onSelectVariant: _selectVariant,
                ),
            ],
          );
        },
      ),
    );
  }

  /// What the pill says, in the order the stages actually happen.
  ///
  /// Capturing and processing win over the tracking states: both run while a
  /// quad is still locked on screen, and "Mengunci..." over a request in
  /// flight would say the scanner was still deciding.
  ScanPillStatus _pillStatus(ScanState scanState) {
    if (_capturing) return ScanPillStatus.capturing;
    if (scanState is ScanLoading) return ScanPillStatus.processing;
    if (_paused) return ScanPillStatus.paused;
    if (_activeTempId != null) return ScanPillStatus.done;
    if (_locking || _cardDetected) return ScanPillStatus.locking;
    return ScanPillStatus.searching;
  }

  /// Web's `handleTogglePause`. Resuming starts the lock from scratch: a
  /// stability count carried across the pause would fire on a card the user
  /// never held still.
  void _togglePause() {
    _autoCapture.reset();
    setState(() {
      _paused = !_paused;
      _cardDetected = false;
      _locking = false;
    });
  }

  Future<void> _toggleSound() async {
    final sound = ref.read(scanSoundProvider);
    await sound.setMuted(!sound.muted);
    if (mounted) setState(() {});
  }

  Widget _buildPreview(Size screenSize) {
    final error = _cameraError;
    if (error != null) {
      return _CameraUnavailable(
        message: error,
        onRetry: () => setState(() => _initialization = _startCamera()),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return FutureBuilder<void>(
        future: _initialization,
        builder: (context, _) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final previewSize = controller.value.previewSize;
    // `cover`, matching what `guideRectInImageSpace` assumes — an inner
    // FittedBox rather than CameraPreview alone, which would letterbox.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize?.height ?? screenSize.width,
          height: previewSize?.width ?? screenSize.height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.imageOff, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body(Colors.white70),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Warps and encodes off the UI thread — a 1400px warp plus a JPEG encode is
/// tens of milliseconds, and the preview should stay smooth at exactly the
/// moment of capture.
