import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../repository/models/scan_models.dart';
import '../repository/scanner_repository.dart';
import '../usecase/scan_session_notifier.dart';
import '../usecase/scanner_notifier.dart';
import '../usecase/scan_sound.dart';
import '../utils/auto_capture.dart';
import '../utils/card_appearance.dart';
import '../utils/scanner_camera_session.dart';
import '../utils/scan_debug_dump.dart';
import '../utils/scan_retry.dart';
import '../utils/card_detector.dart';
import '../utils/detector_worker.dart';
import '../utils/card_capture.dart';
import '../utils/corner_model.dart';
import '../utils/warp_quad.dart';
import 'widgets/scan_hint.dart';
import 'widgets/scan_candidate_sheet.dart';
import 'widgets/scan_card_search_sheet.dart';
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
  /// How often the detector samples the stream. Ports the web's poll rate.
  static const _tickInterval = Duration(milliseconds: 120);

  static const _burstFrames = 2;

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

  late final _cameraSession = ScannerCameraSession<CameraController>(
    open: _openCamera,
    close: (controller) async {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } finally {
        await controller.dispose();
      }
    },
  );
  CameraController? get _controller => _cameraSession.current;
  var _foreground = true;
  int _lastFrameSequence = 0;
  int _frameSequence = 0;
  DateTime? _frameAt;
  DateTime? _lastFocusAt;
  DateTime? _lastDiagnosticAt;
  int _diagnosticTicks = 0;
  double _prepareMsTotal = 0;
  double _inferenceMsTotal = 0;
  final _gateCounts = <String, int>{};
  String? _detectorError;
  bool _retrying = false;
  Timer? _recoveryTimer;
  int _recoveryAttempts = 0;
  int _cameraRecoveryAttempts = 0;
  Future<void>? _detectorStartup;
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
    unawaited(_keepAwake(true));
    _initialization = _startCamera();
    unawaited(_prepareDetector());
  }

  Future<void> _keepAwake(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (e) {
      debugPrint('[scan] keep-awake failed: $e');
    }
  }

  void _scheduleDetectorRecovery() {
    if (!mounted || (_recoveryTimer?.isActive ?? false)) return;
    // Back off repeated startup faults; keep the camera preview visible.
    final delay = Duration(seconds: _recoveryAttempts < 3 ? 1 : 5);
    _recoveryTimer = Timer(delay, () async {
      if (!mounted || !_foreground) return;
      if (_detecting || _capturing || _retrying) {
        _scheduleDetectorRecovery();
        return;
      }
      _recoveryAttempts++;
      await _worker?.dispose();
      _worker = null;
      _autoCapture.reset();
      if (mounted) await _prepareDetector();
    });
  }

  Future<void> _prepareDetector() => _detectorStartup ??= _loadDetector()
      .whenComplete(() => _detectorStartup = null);

  Future<void> _loadDetector() async {
    try {
      _worker ??= await DetectorWorker.spawn();
      _model ??= await CornerModel.load();
      if (!mounted) {
        await _worker?.dispose();
        return;
      }
      setState(() => _detectorError = null);
    } catch (e) {
      debugPrint('[scan] detector startup failed: $e');
      if (mounted) {
        setState(() => _detectorError = 'Menyiapkan pemindai...');
        _scheduleDetectorRecovery();
      }
    }
  }

  @override
  void dispose() {
    unawaited(_keepAwake(false));
    _recoveryTimer?.cancel();
    _worker?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _rearmTimer?.cancel();
    _burstTimer?.cancel();
    _hintTimer?.cancel();
    _tickTimer?.cancel();
    unawaited(
      _cameraSession.stop().catchError((Object e) {
        debugPrint('[scan] camera release failed: $e');
      }),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      if (_foreground) return;
      _foreground = true;
      unawaited(_keepAwake(true));
      if (_detectorError != null) _scheduleDetectorRecovery();
      setState(() => _initialization = _startCamera());
    } else if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.detached) {
      if (!_foreground) return;
      _foreground = false;
      unawaited(_keepAwake(false));
      _tickTimer?.cancel();
      _latestFrame = null;
      _frameAt = null;
      _autoCapture.reset();
      unawaited(
        _cameraSession.stop().catchError((Object e) {
          debugPrint('[scan] camera release failed: $e');
        }),
      );
      setState(() {
        _cardDetected = false;
        _locking = false;
      });
    }
  }

  Future<void> _startCamera() async {
    final opening = _cameraSession.start();
    final generation = _cameraSession.generation;
    try {
      await opening;
      if (!mounted || !_foreground || !_cameraSession.isCurrent(generation)) {
        return;
      }
      final controller = _controller;
      if (controller == null) return;
      setState(() {
        _cameraError = null;
        _torchOn = false;
      });
      _hintTimer ??= Timer(_hintVisibleFor, () {
        if (mounted) setState(() => _hintVisible = false);
      });
      await _startDetection(controller);
    } catch (e) {
      if (!mounted || !_foreground || !_cameraSession.isCurrent(generation)) {
        return;
      }
      debugPrint('[scan] camera startup failed: $e');
      setState(() {
        _cameraError = e is CameraException && e.code == 'CameraAccessDenied'
            ? 'Izin kamera ditolak. Aktifkan di pengaturan aplikasi.'
            : 'Kamera gagal dimulai. Coba lagi.';
      });
    }
  }

  Future<CameraController> _openCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw CameraException('NoCamera', 'Kamera tidak tersedia');
    }
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      back,
      // 720p retains more detail than the 768px working frame while reducing
      // native-to-Dart camera traffic by over half versus 1080p.
      ResolutionPreset.high,
      // Request a smooth preview; detection samples the latest frame separately.
      fps: Platform.isIOS ? 60 : 30,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await controller.setExposureMode(ExposureMode.auto);
      } on CameraException {
        // Fixed-focus cameras still support scanning.
      }
      try {
        await controller.setZoomLevel(1);
      } on CameraException {
        // Some devices do not expose zoom controls.
      }
      await controller.startImageStream((frame) {
        if (!mounted || !_foreground || !identical(controller, _controller)) {
          return;
        }
        _latestFrame = frame;
        _frameAt = DateTime.now();
        _frameSequence++;
        _cameraRecoveryAttempts = 0;
      });
      return controller;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  /// The guide box in screen coordinates, at exactly [cardAspect].
  /// Frames stream in; a timer samples the newest one every
  /// [_tickInterval].
  ///
  /// Separate stream and tick on purpose: frames arrive faster than detection
  /// can keep up, so sampling on a timer keeps the cadence
  /// predictable and always works on the most recent pose.
  Future<void> _startDetection(CameraController controller) async {
    _latestFrame = null;
    _frameAt = DateTime.now();
    _lastDiagnosticAt = null;
    if (!mounted || !_foreground || !identical(controller, _controller)) return;
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

  Future<void> _focusOnCard(Quad quad, FramePrep prep) async {
    final controller = _controller;
    final now = DateTime.now();
    if (controller == null ||
        (_lastFocusAt != null &&
            now.difference(_lastFocusAt!) < const Duration(seconds: 2))) {
      return;
    }
    _lastFocusAt = now;
    final bounds = quad.bounds;
    try {
      await controller.setFocusPoint(
        Offset(
          ((bounds.left + bounds.right) / (2 * prep.width)).clamp(0.0, 1.0),
          ((bounds.top + bounds.bottom) / (2 * prep.height)).clamp(0.0, 1.0),
        ),
      );
    } on CameraException {
      // Continuous autofocus remains active if point focus isn't supported.
    }
  }

  Future<void> _tick() async {
    if (!mounted ||
        !_foreground ||
        _detecting ||
        _capturing ||
        _paused ||
        _sessionOpen ||
        (_rearmTimer?.isActive ?? false) ||
        _detectorError != null) {
      return;
    }
    final model = _model;
    final frame = _latestFrame;
    final controller = _controller;
    if (_frameAt != null &&
        DateTime.now().difference(_frameAt!) > const Duration(seconds: 3)) {
      _tickTimer?.cancel();
      unawaited(
        recordScanEvent({
          'stage': 'camera_stalled',
          'attempt': _cameraRecoveryAttempts + 1,
        }),
      );
      if (_cameraRecoveryAttempts++ < 3) {
        // A live detector cannot recover a stopped native image stream.
        // Reopen the camera automatically, preserving the scan session.
        _latestFrame = null;
        _autoCapture.reset();
        setState(() => _initialization = _startCamera());
      } else {
        setState(() => _cameraError = 'Kamera terhenti. Coba lagi.');
      }
      return;
    }
    if (model == null || frame == null || controller == null) return;
    if (ref.read(scannerProvider) is ScanLoading) return;
    if (_frameSequence == _lastFrameSequence) return;
    _lastFrameSequence = _frameSequence;
    final generation = _cameraSession.generation;
    bool current() =>
        mounted &&
        _foreground &&
        _cameraSession.isCurrent(generation) &&
        !_paused &&
        !_sessionOpen;
    final capturedAt = _frameAt!;
    _detecting = true;
    final watch = Stopwatch()..start();
    try {
      // Decode, orient and build the first tensor on the worker's isolate.
      // This is the pixel work that used to block the UI thread every tick.
      final prep = await _worker?.prepareFrame(
        frame,
        _frameRotation(controller),
      );
      if (prep == null || !current()) return;

      _recoveryAttempts = 0;
      final prepareMs = watch.elapsedMicroseconds / 1000;
      // Coarse only: the second stage is for the frame about to be sent,
      // not for tracking.
      final raw = await model.run(prep.tensor, prep.region);
      final inferenceMs = watch.elapsedMicroseconds / 1000 - prepareMs;
      if (!current()) return;
      final rejection = raw == null
          ? 'inference'
          : detectionRejection(raw, prep.region);
      final detection = rejection == null ? raw : null;
      if (detection != null && !_cardDetected) {
        unawaited(_focusOnCard(detection.quad, prep));
      }
      _recordDiagnostic(
        prep,
        raw,
        rejection,
        prepareMs,
        inferenceMs,
        DateTime.now().difference(capturedAt).inMilliseconds,
      );
      if (!current()) return;
      final wasWaiting = _autoCapture.waitingForRemoval;
      final result = _autoCapture.tick(
        detection?.quad,
        DateTime.now(),
        appearance: detection == null
            ? null
            : cardAppearance(prep.tensor, prep.region, detection.quad),
      );
      final detected = result.quad != null;
      final locking = result.progress > 0 && result.progress < 1;
      final clearPrevious =
          _activeTempId != null &&
          (!detected ||
              !_autoCapture.waitingForRemoval ||
              _autoCapture.replacingCapturedCard);
      if (detected != _cardDetected ||
          locking != _locking ||
          clearPrevious ||
          wasWaiting != _autoCapture.waitingForRemoval) {
        setState(() {
          _cardDetected = detected;
          _locking = locking;
          if (clearPrevious) {
            _activeTempId = null;
            _burstCardId = null;
          }
        });
      }

      if (result.action == AutoCaptureAction.capture && result.quad != null) {
        await _captureQuad(
          model,
          normalizedCard: result.quad!.offsetBy(
            0,
            0,
            scaleX: 1 / prep.width,
            scaleY: 1 / prep.height,
          ),
        );
      }
    } catch (e) {
      debugPrint('[scan] detection failed: $e');
      unawaited(recordScanEvent({'stage': 'error', 'error': e.toString()}));
      _autoCapture.reset();
      if (current()) {
        setState(() {
          _cardDetected = false;
          _locking = false;
          _detectorError = 'Menyiapkan pemindai...';
        });
        _scheduleDetectorRecovery();
      }
    } finally {
      _detecting = false;
    }
  }

  void _recordDiagnostic(
    FramePrep prep,
    Detection? detection,
    String? rejection,
    double prepareMs,
    double inferenceMs,
    int frameAgeMs,
  ) {
    if (!scanDiagnosticsEnabled) return;
    _diagnosticTicks++;
    _prepareMsTotal += prepareMs;
    _inferenceMsTotal += inferenceMs;
    final gate = rejection ?? 'accepted';
    _gateCounts[gate] = (_gateCounts[gate] ?? 0) + 1;
    final now = DateTime.now();
    if (_lastDiagnosticAt != null &&
        now.difference(_lastDiagnosticAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastDiagnosticAt = now;
    final meta = <String, dynamic>{
      'stage': 'live',
      'rejection': rejection,
      'prepareMs': prepareMs,
      'inferenceMs': inferenceMs,
      'frameAgeMs': frameAgeMs,
      'ticks': _diagnosticTicks,
      'meanPrepareMs': _prepareMsTotal / _diagnosticTicks,
      'meanInferenceMs': _inferenceMsTotal / _diagnosticTicks,
      'gates': Map.of(_gateCounts),
      'width': prep.width,
      'height': prep.height,
      'presence': detection?.present.isFinite == true
          ? detection?.present
          : null,
      'corners': detection?.quad.corners
          .map((p) => [p.x.isFinite ? p.x : null, p.y.isFinite ? p.y : null])
          .toList(),
      'waitingForRemoval': _autoCapture.waitingForRemoval,
    };
    _diagnosticTicks = 0;
    _prepareMsTotal = 0;
    _inferenceMsTotal = 0;
    _gateCounts.clear();
    unawaited(recordScanEvent(meta));
    // Optional frame dumps never block the live detector or fail its tick.
    if (scanSaveFrames && _worker != null) {
      unawaited(
        saveDiagnosticSnapshot(
          _worker!,
          meta,
          tag: rejection == null ? 'scan_live' : 'scan_rejected',
        ),
      );
    }
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
    return passesGates(
              stage2,
              region,
              aspectTolerance: stage2AspectTolerance,
            ) &&
            refinementAgrees(stage1.quad, stage2.quad)
        ? stage2
        : stage1;
  }

  /// Keeps a detailed burst frame, re-detects on that exact frame, then warps.
  /// The live quad only identifies the region to compare focus in; it is
  /// never reused for cropping a later frame or a different resolution.
  Future<void> _captureQuad(
    CornerModel model, {
    required Quad normalizedCard,
  }) async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _activeTempId = null;
      _hintVisible = false;
    });
    _rearmTimer?.cancel();
    final generation = _cameraSession.generation;
    bool current() =>
        mounted && _foreground && _cameraSession.isCurrent(generation);
    var keepDisarmed = false;
    Duration? retryAfter;
    final captureWatch = Stopwatch()..start();

    try {
      final worker = _worker;
      final controller = _controller;
      if (worker == null || controller == null) return;

      final orientation = _frameRotation(controller);

      // The burst: two frames a gap apart, sharpest kept. A hand is never
      // still, and one grab lands on the blurred half of that wobble often
      // enough to be the difference between a match and a miss.
      await worker.beginBurst(normalizedCard: normalizedCard);
      if (!current()) return;
      int? offeredSequence;
      for (var i = 0; i < _burstFrames; i++) {
        final wait = Stopwatch()..start();
        while (_frameSequence == offeredSequence &&
            current() &&
            wait.elapsedMilliseconds < 250) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        if (_frameSequence == offeredSequence) break;
        final frame = _latestFrame;
        if (frame == null || !current()) return;
        offeredSequence = _frameSequence;
        await worker.offerBurstFrame(frame, orientation);
      }
      if (!current()) return;

      final prep = await worker.burstTensor();
      if (prep == null || !current()) return;

      final burstMs = captureWatch.elapsedMilliseconds;
      // Tier one: detect on the frame being sent.
      final fresh = await _detect(model, prep);
      final detectMs = captureWatch.elapsedMilliseconds - burstMs;
      if (!current()) return;
      final quad = fresh?.quad;
      const tier = 'model';
      final tierPresence = fresh?.present ?? 0;

      if (quad == null) {
        // Web's miss branch: re-arm and say so rather than sending anything.
        _autoCapture.reset();
        return;
      }

      final capture = await worker.warpBurst(quad);
      if (capture == null || !current()) return;

      if (scanDiagnosticsEnabled) {
        final meta = <String, dynamic>{
          'stage': 'capture',
          'burstMs': burstMs,
          'detectMs': detectMs,
          'warpMs': captureWatch.elapsedMilliseconds - burstMs - detectMs,
          'tier': tier,
          'presence': tierPresence,
          'sharpness': capture.sharpness,
          'luma': capture.luma,
          'bytes': capture.bytes.length,
          'corners': quad.corners.map((p) => [p.x, p.y]).toList(),
          'width': prep.width,
          'height': prep.height,
        };
        unawaited(recordScanEvent(meta));
        if (scanSaveFrames) {
          unawaited(saveDiagnosticSnapshot(worker, meta, tag: 'scan_source'));
        }
      }
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
      if (!current()) return;

      if (result is ScanMatched) {
        keepDisarmed = true;
        final chosen = result.confident
            ? result.card
            : await _chooseUncertainMatch(result);
        if (!current() || chosen == null) return;
        // The same card twice in a row is usually the scanner having fired
        // again on a card still in shot, not someone holding two copies. It
        // is a real case though — playsets are four of one card — so it is a
        // question rather than a refusal, and the answer is theirs.
        if (chosen.id == _lastCapturedCardId) {
          final again = await _confirmDuplicate(chosen);
          if (!current() || !again) {
            // Declined: nothing is added, and the machine is left as the
            // fire put it — suspended until the card moves or leaves. A
            // `reset()` here would re-arm on the card still sitting in shot
            // and ask the same question again a second later.
            return;
          }
        }
        _addMatch(result, chosen);
      } else if (result is ScanFailed) {
        retryAfter = result.retryAfter;
        _showError(result.message);
        // Let the same card be retried without moving it.
        _autoCapture.reset();
      }
    } catch (e) {
      debugPrint('[scan] capture failed: $e');
      if (current()) _showError('Pindai gagal. Tahan kartu dan coba lagi.');
    } finally {
      if (!keepDisarmed) _autoCapture.reset();
      if (mounted) {
        setState(() => _capturing = false);
        _scheduleRearm(after: retryAfter);
      }
    }
  }

  Future<ScanCard?> _chooseUncertainMatch(ScanMatched result) =>
      showModalBottomSheet<ScanCard>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => ScanCandidateSheet(
          candidates: result.matches.map((match) => match.card).toList(),
          onSelect: (card) => Navigator.of(sheetContext).pop(card),
          onSearch: () async {
            final picked = await showModalBottomSheet<ScanCard>(
              context: sheetContext,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (searchContext) => ScanCardSearchSheet(
                language: ref.read(scanLanguageProvider),
                onSelect: (card) => Navigator.of(searchContext).pop(card),
              ),
            );
            if (picked != null && sheetContext.mounted) {
              Navigator.of(sheetContext).pop(picked);
            }
          },
        ),
      );

  /// Only a confident response or an explicit selection reaches this point.
  void _addMatch(ScanMatched result, ScanCard chosen) {
    if (!result.confident && result.logId != null) {
      unawaited(
        ref
            .read(scannerRepositoryProvider)
            .confirmChoice(logId: result.logId!, chosenCardId: chosen.id),
      );
    }
    final tempId = ref
        .read(scanSessionProvider.notifier)
        .addItem(
          card: chosen,
          variants: chosen.id == result.card.id ? result.variants : [chosen],
          needsReview: false,
          logId: result.logId,
        );
    setState(() {
      _activeTempId = tempId;
      _lastCapturedCardId = chosen.id;
      _burstCardId = chosen.id;
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
    final delay = scanRetryDelay(
      retryAfter: after,
      jitter: _jitter.nextDouble(),
    );
    _rearmTimer = Timer(delay, () {
      if (mounted) {
        ref.read(scannerProvider.notifier).reset();
        setState(() {});
      }
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
    _autoCapture.reset();
    ref.read(scannerProvider.notifier).reset();
    setState(() {
      _activeTempId = null;
      _cardDetected = false;
      _locking = false;
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
    if (_detectorError != null) return ScanPillStatus.recovering;
    if (!_capturing &&
        scanState is! ScanLoading &&
        _autoCapture.waitingForRemoval &&
        _activeTempId == null) {
      return ScanPillStatus.moveCard;
    }
    return scannerPillStatus(
      processing: scanState is ScanLoading,
      capturing: _capturing,
      paused: _paused,
      coolingDown: scanState is ScanFailed && (_rearmTimer?.isActive ?? false),
      capturedCardPresent:
          _cardDetected &&
          _autoCapture.waitingForRemoval &&
          _activeTempId != null,
      tracking: _locking || _cardDetected,
    );
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
        onRetry: () async {
          if (_retrying || _detecting || _capturing) return;
          _retrying = true;
          try {
            await _detectorStartup;
            await _worker?.dispose();
            _worker = null;
            _autoCapture.reset();
            if (!mounted) return;
            await _prepareDetector();
            if (mounted && _foreground) {
              setState(() => _initialization = _startCamera());
            }
          } finally {
            _retrying = false;
          }
        },
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
