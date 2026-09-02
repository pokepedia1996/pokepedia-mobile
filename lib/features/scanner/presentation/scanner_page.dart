import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../repository/models/scan_models.dart';
import '../repository/scanner_repository.dart';
import '../usecase/scan_session_notifier.dart';
import '../usecase/scanner_notifier.dart';
import '../usecase/scan_sound.dart';
import '../utils/auto_capture.dart';
import '../utils/camera_frame.dart';
import '../utils/card_capture.dart';
import '../utils/corner_model.dart';
import '../utils/warp_quad.dart';
import 'widgets/scan_lock_overlay.dart';
import 'widgets/scan_result_sheet.dart';
import 'widgets/scan_session_sheet.dart';
import 'widgets/scan_status_pill.dart';
import 'widgets/scanner_top_bar.dart';

/// Ports `features/scanner/components/ScannerView.tsx`.
///
/// ## What's the same, and what deliberately isn't
///
/// The web runs a corner-detection model over the live feed and fires capture
/// automatically once a detected quad holds still. That whole tier is replaced
/// here by a drawn guide box the user aligns against and a shutter they press
/// — see the header comment in `utils/card_capture.dart` for why. Everything
/// downstream of the capture is a faithful port: the same endpoint, the same
/// confidence recomputation, the same batch semantics, the same two terminal
/// actions.
///
/// The pieces of ScannerView that *are* carried over verbatim are the ones
/// that stop a fast scanning run from corrupting itself:
///
///  * a **generation guard** (in `ScannerNotifier`) so a slow earlier response
///    can't overwrite a newer scan's result;
///  * a **single-flight gate** so a double-tap can't put two captures in
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

  /// Newest frame off the stream. Held, not queued: detection is slower than
  /// frames arrive, and a queue would work through stale poses instead of
  /// looking at what the camera sees now.
  CameraImage? _latestFrame;

  bool _detecting = false;
  Timer? _tickTimer;
  final _autoCapture = AutoCaptureMachine();

  /// What the hint text reflects.
  bool _cardDetected = false;
  bool _locking = false;

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
          if (kDebugMode) debugPrint('[scan] model load failed: $e');
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rearmTimer?.cancel();
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
      if (kDebugMode) debugPrint('[scan] image stream failed: $e');
      return;
    }
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (!mounted || _detecting || _capturing) return;
    final model = _model;
    final frame = _latestFrame;
    final controller = _controller;
    if (model == null || frame == null || controller == null) return;
    if (ref.read(scannerProvider) is ScanLoading) return;

    _detecting = true;
    try {
      final rgb = frameToImage(frame);
      if (rgb == null || !mounted) return;

      final upright = orientFrame(
        rgb,
        controller.description.sensorOrientation,
      );
      final detection = await detectCardTwoStage(model, upright);
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
          upright,
          result.quad!,
          presence: detection?.present ?? 0,
        );
      }
    } finally {
      _detecting = false;
    }
  }

  /// Warps the locked quad out of the frame it was detected in and scans it.
  ///
  /// The same frame detection ran on, not a fresh still: the quad's
  /// coordinates only mean anything there, and a `takePicture` between lock
  /// and capture would move the card out from under them.
  Future<void> _captureQuad(
    img.Image frame,
    Quad quad, {
    required double presence,
  }) async {
    if (_capturing) return;
    setState(() => _capturing = true);
    _rearmTimer?.cancel();

    try {
      final capture = await compute(_warpInIsolate, (frame: frame, quad: quad));
      if (!mounted) return;

      final result = await ref
          .read(scannerProvider.notifier)
          .scan(
            capture: capture,
            language: ref.read(scanLanguageProvider),
            captureMeta: _quadCaptureMeta(frame, capture, quad, presence),
          );
      if (!mounted) return;

      if (result is ScanMatched) {
        final tempId = ref
            .read(scanSessionProvider.notifier)
            .addItem(
              card: result.card,
              variants: result.variants,
              needsReview: !result.confident,
              logId: result.logId,
            );
        setState(() => _activeTempId = tempId);
        // Fired once per card that actually lands, matching web. With no
        // shutter this is the only confirmation the user gets — they are
        // looking at the card in their hand, not the screen.
        unawaited(ref.read(scanSoundProvider).play());
      } else if (result is ScanFailed) {
        _showError(result.message);
        // Let the same card be retried without moving it.
        _autoCapture.reset();
      }
      _scheduleRearm(after: result is ScanFailed ? result.retryAfter : null);
    } catch (e) {
      if (!mounted) return;
      if (kDebugMode) debugPrint('[scan] capture failed: $e');
      _showError('Gagal memproses gambar');
      _autoCapture.reset();
      _scheduleRearm();
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Map<String, dynamic> _quadCaptureMeta(
    img.Image frame,
    CardCapture capture,
    Quad quad,
    double presence,
  ) {
    final controller = _controller;
    final bounds = quad.bounds;
    return {
      'label': controller?.description.name ?? '',
      'deviceId': controller?.description.name ?? '',
      'trackWidth': frame.width,
      'trackHeight': frame.height,
      'pinnedToSingleLens': true,
      'videoWidth': frame.width,
      'videoHeight': frame.height,
      'cropWidth': (bounds.right - bounds.left).round().clamp(0, 20000),
      'cropHeight': (bounds.bottom - bounds.top).round().clamp(0, 20000),
      'outWidth': capture.width,
      'outHeight': capture.height,
      'sharpness': capture.sharpness.round().clamp(0, 1000000),
      'luma': capture.luma.round().clamp(0, 255),
      'cropTier': 'model',
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
    setState(() => _activeTempId = null);
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
              ScanLockOverlay(detected: _cardDetected, locking: _locking),
              Positioned(
                top: MediaQuery.of(context).padding.top + 64,
                left: 0,
                right: 0,
                child: Center(
                  child: ScanStatusPill(
                    status: _capturing
                        ? ScanPillStatus.capturing
                        : scanState is ScanLoading
                        ? ScanPillStatus.processing
                        : ScanPillStatus.ready,
                  ),
                ),
              ),
              ScannerTopBar(
                language: language,
                onLanguageChanged: _onLanguageChanged,
                busy: _capturing || scanState is ScanLoading,
                torchSupported: _torchSupported,
                torchOn: _torchOn,
                onToggleTorch: _toggleTorch,
                onClose: () => Navigator.of(context).maybePop(),
              ),
              ScanResultSheet(
                item: activeItem,
                sessionCount: session.fold(
                  0,
                  (sum, item) => sum + item.quantity,
                ),
                busy: _capturing || scanState is ScanLoading,
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
CardCapture _warpInIsolate(({img.Image frame, Quad quad}) args) =>
    captureFromQuad(args.frame, args.quad);
