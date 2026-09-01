import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_typography.dart';
import '../../../shared/models/card_model.dart';
import '../repository/models/scan_models.dart';
import '../repository/scanner_repository.dart';
import '../usecase/scan_session_notifier.dart';
import '../usecase/scanner_notifier.dart';
import '../utils/card_capture.dart';
import 'widgets/scan_guide_overlay.dart';
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
  /// Fraction of the screen width the guide box spans. Wide enough that a card
  /// held at a comfortable distance fills it — "near-filling" is the framing
  /// the embedder's catalog renders are closest to.
  static const _guideWidthFraction = 0.84;

  /// Ceiling on the guide box's height as a fraction of screen height, so the
  /// box still fits (with room for the controls) on a short screen.
  static const _guideMaxHeightFraction = 0.62;

  /// How long a result stays up before the shutter re-arms. Ports
  /// `SCAN_RESULT_SETTLE_MS`.
  static const _resultSettle = Duration(milliseconds: 900);

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rearmTimer?.cancel();
    _controller?.dispose();
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
      unawaited(controller.dispose());
      if (mounted) setState(() {});
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
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      // Locked so the guide box and the still stay in the same coordinate
      // space — a rotation between framing and capture would offset every crop.
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraError = null;
      });
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
  Rect _guideRect(Size screenSize) {
    var width = screenSize.width * _guideWidthFraction;
    var height = width / cardAspect;
    final maxHeight = screenSize.height * _guideMaxHeightFraction;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * cardAspect;
    }
    return Rect.fromCenter(
      // Sat slightly above centre so the result sheet doesn't cover the card
      // the user is still holding in frame.
      center: Offset(screenSize.width / 2, screenSize.height * 0.44),
      width: width,
      height: height,
    );
  }

  Future<void> _capture(Size screenSize) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_capturing) return;
    if (ref.read(scannerProvider) is ScanLoading) return;

    setState(() => _capturing = true);
    _rearmTimer?.cancel();

    try {
      final shot = await controller.takePicture();
      final frameBytes = await shot.readAsBytes();

      // The preview is painted `cover`, so the guide box must be mapped out of
      // screen space before it means anything against the still.
      final previewSize = controller.value.previewSize;
      // `previewSize` is reported in sensor (landscape) orientation while the
      // preview is painted portrait — swapping here is what keeps the mapping
      // honest on a portrait-locked screen.
      final displayedPreview = previewSize == null
          ? screenSize
          : Size(previewSize.height, previewSize.width);
      final cropRect = guideRectInImageSpace(
        previewSize: displayedPreview,
        screenSize: screenSize,
        guideRect: _guideRect(screenSize),
      );

      final capture = await cropCardFromFrame(
        frameBytes: frameBytes,
        cropRectInImageSpace: cropRect,
        imageSize: displayedPreview,
      );
      if (!mounted) return;

      if (capture == null) {
        ref.read(scannerProvider.notifier).setError('Gagal memproses gambar');
        _scheduleRearm();
        return;
      }

      final language = ref.read(scanLanguageProvider);
      final result = await ref
          .read(scannerProvider.notifier)
          .scan(
            capture: capture,
            language: language,
            captureMeta: {
              'label': controller.description.name,
              'deviceId': controller.description.name,
              'trackWidth': displayedPreview.width.round(),
              'trackHeight': displayedPreview.height.round(),
              'pinnedToSingleLens': true,
              'videoWidth': displayedPreview.width.round(),
              'videoHeight': displayedPreview.height.round(),
              'cropWidth': cropRect.width.round().clamp(0, 20000),
              'cropHeight': cropRect.height.round().clamp(0, 20000),
              'outWidth': capture.width,
              'outHeight': capture.height,
              'sharpness': capture.sharpness.round().clamp(0, 1000000),
              'luma': capture.luma.round().clamp(0, 255),
            },
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
      } else if (result is ScanFailed) {
        _showError(result.message);
      }
      _scheduleRearm();
    } on CameraException catch (e) {
      if (!mounted) return;
      _showError('Gagal mengambil gambar (${e.code})');
      _scheduleRearm();
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Returns the scanner to idle once the result has had a moment to register,
  /// so the status pill and shutter reflect "ready" again.
  void _scheduleRearm() {
    _rearmTimer?.cancel();
    _rearmTimer = Timer(_resultSettle, () {
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
              ScanGuideOverlay(guideRect: _guideRect(screenSize)),
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
                onCapture: () => _capture(screenSize),
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
            const Icon(Icons.no_photography_outlined,
                color: Colors.white54, size: 48),
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
