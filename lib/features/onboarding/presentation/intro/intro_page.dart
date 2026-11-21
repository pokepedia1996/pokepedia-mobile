import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/auth_errors.dart';
import '../../../../shared/widgets/coretan_kit.dart';
import '../../../../shared/widgets/scribble_drawing.dart';
import '../../usecase/intro_flag.dart';
import '../onb_style.dart';
import '../onb_widgets.dart';
import 'intro_slides.dart';

const _last = 6;

/// How a footer child is moving: opacity and downward offset.
typedef _Move = ({double o, double dy});

/// First-launch intro: a welcome, five feature slides and the Daftar screen.
///
/// Geometry is `pokepad.pen` "Onboarding Baru 0–6" at its own pixel values;
/// the motion is `animasi-onboarding/index.html`'s `go()` and `start()`,
/// timing for timing. It is driven by hand rather than by a `PageView`: the
/// old slide leaves (the drawing slides, tilts and fades; the copy goes
/// line by line), the new one enters after a beat, and going to or from
/// Daftar swaps the layout only while everything is faded out.
///
/// Shown once, before sign-in, and never to a signed-in user (the router
/// sends them to Beranda). Leaving by any door sets [IntroFlag].
class IntroPage extends ConsumerStatefulWidget {
  const IntroPage({super.key});

  @override
  ConsumerState<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends ConsumerState<IntroPage>
    with TickerProviderStateMixin {
  /// Drives one slide change; its length is set per change.
  late final _tx = AnimationController(vsync: this);

  /// The first open: copy rising in, then the footer.
  late final _boot = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  /// The stage fading in, as the prototype's `.boot` does.
  late final _stage = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..forward();

  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;
  Timer? _busyTimer;

  int _idx = 0;
  int _prev = -1;
  int _dir = 1;

  /// A change is under way; the next tap waits, and the last one wins.
  bool _busy = false;
  int? _queued;

  /// Whether this change moves to or from Daftar, and so swaps the layout
  /// at [_enterAt] instead of changing it in place.
  bool _layoutTx = false;
  double _enterAt = 0;

  double _dragDx = 0;
  String? _authBusy;
  String? _authError;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => context.push(Routes.terms('syarat-dan-ketentuan'));
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => context.push(Routes.terms('kebijakan-privasi'));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decoded before the first transition, so it does not stutter.
    for (final path in _precache) {
      precacheImage(AssetImage(path), context).ignore();
    }
  }

  @override
  void dispose() {
    _busyTimer?.cancel();
    _termsTap.dispose();
    _privacyTap.dispose();
    _tx.dispose();
    _boot.dispose();
    _stage.dispose();
    super.dispose();
  }

  double get _txMs => _prev < 0 ? 0 : _tx.value * _tx.duration!.inMilliseconds;
  double get _bootMs => _boot.value * 1100;

  void _go(int i, {int? dir}) {
    if (i == _idx || i < 0 || i > _last) return;
    if (_busy) {
      _queued = i;
      return;
    }
    if (coretanReduceMotion(context)) {
      setState(() {
        _idx = i;
        _prev = -1;
      });
      return;
    }
    final from = _idx;
    final layout = (i == _last) != (from == _last);
    _enterAt = layout ? 280 : 130;
    // Longest of what enters: the drawing (460), the copy (110 + 65·k + 440
    // for three lines), and on a layout change the footer's children.
    var enterEnd = 110 + 65 * 2 + 440.0;
    if (layout) {
      final children = i == _last ? 6 : 2;
      enterEnd = math.max(enterEnd, 150 + 55 * (children - 1) + 440.0);
    }
    _busy = true;
    setState(() {
      _prev = from;
      _idx = i;
      _dir = dir ?? (i > from ? 1 : -1);
      _layoutTx = layout;
    });
    _tx.duration = Duration(milliseconds: (_enterAt + enterEnd).round());
    _tx.forward(from: 0).whenComplete(() {
      if (mounted) {
        setState(() {
          _prev = -1;
          _layoutTx = false;
        });
      }
    });
    _busyTimer?.cancel();
    _busyTimer = Timer(Duration(milliseconds: (_enterAt + 300).round()), () {
      _busy = false;
      final queued = _queued;
      _queued = null;
      if (queued != null && mounted) _go(queued);
    });
  }

  Future<void> _social(
    String provider,
    Future<({bool signedIn, String? error})> Function() run,
  ) async {
    if (_authBusy != null) return;
    setState(() {
      _authBusy = provider;
      _authError = null;
    });
    ({bool signedIn, String? error}) result;
    try {
      result = await run();
    } catch (e) {
      // Whatever it was, the buttons must not stay dead.
      result = (signedIn: false, error: '$e');
    }
    if (!mounted) return;
    if (result.signedIn) {
      await IntroFlag.markDone();
      // A new account gets `OnboardingGate` over Beranda; a returning one
      // just lands there.
      if (mounted) context.go(Routes.home);
      return;
    }
    setState(() {
      _authBusy = null;
      // Cancelling the sheet is `(false, null)`: nothing to report.
      final error = result.error;
      _authError = error == null
          ? null
          : translateAuthError(error, provider: provider);
    });
  }

  Future<void> _leaveTo(void Function() go) async {
    await IntroFlag.markDone();
    if (mounted) go();
  }

  @override
  Widget build(BuildContext context) {
    // The paper and its ink are light only: read inside the locked theme.
    return Theme(
      data: AppTheme.light,
      child: Builder(builder: _stageScaffold),
    );
  }

  /// Whether the layout is Daftar's at [ms] into the current change.
  bool _compactAt(double ms) {
    if (!_layoutTx) return _idx == _last;
    return ms >= _enterAt ? _idx == _last : _prev == _last;
  }

  Widget _stageScaffold(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: PopScope(
          canPop: _idx == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _go(_idx - 1);
          },
          child: Scaffold(
            backgroundColor: AppColors.onbCream,
            body: FadeTransition(
              opacity: _stage,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) => _dragDx = 0,
                onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
                onHorizontalDragEnd: (_) {
                  if (_dragDx.abs() > 50) {
                    _dragDx < 0 ? _go(_idx + 1) : _go(_idx - 1);
                  }
                  _dragDx = 0;
                },
                child: ClipRect(
                  child: Stack(
                    children: [
                      _pattern(size),
                      AnimatedBuilder(
                        animation: Listenable.merge([_tx, _boot]),
                        builder: (context, _) {
                          final ms = _txMs;
                          final compact = _compactAt(ms);
                          return Padding(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              math.max(56, insets.top),
                              24,
                              math.max(compact ? 28 : 30, insets.bottom),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _topBar(),
                                Expanded(child: _isi(ms, compact)),
                                _footer(ms),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The energy pattern, on a layer larger than the screen so it can shift
  /// by `(-42·i, -14·i)` with each slide without being redrawn.
  Widget _pattern(Size size) {
    return Positioned(
      left: 0,
      top: 0,
      width: size.width + 420,
      height: size.height + 180,
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: Offset(-_idx * 42.0, -_idx * 14.0)),
        duration: const Duration(milliseconds: 900),
        curve: const Cubic(.3, .7, .2, 1),
        builder: (context, offset, child) =>
            Transform.translate(offset: offset, child: child),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(coretanTileCream),
              repeat: ImageRepeat.repeat,
              // 778 px drawn as 259 pt.
              scale: 3,
              alignment: Alignment.topLeft,
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final slides = _idx >= 1 && _idx <= 4;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          // The slot, back plus the gap, opens and closes so the logo
          // glides instead of jumping.
          TweenAnimationBuilder<double>(
            tween: Tween(end: _idx == 0 ? 0.0 : 1.0),
            duration: const Duration(milliseconds: 400),
            curve: onbOut,
            builder: (context, open, child) => ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: open,
                child: Opacity(
                  opacity: open.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.5 + 0.5 * open,
                    alignment: Alignment.centerLeft,
                    child: child,
                  ),
                ),
              ),
            ),
            child: IgnorePointer(
              ignoring: _idx == 0,
              child: Row(
                children: [
                  OnbRoundBack(onTap: () => _go(_idx - 1)),
                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
          Image.asset(
            'assets/images/horizontal-logo-light.webp',
            width: 128,
            height: 28,
          ),
          const Spacer(),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: slides ? 1 : 0,
            child: IgnorePointer(
              ignoring: !slides,
              child: ExcludeSemantics(
                excluding: !slides,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _go(_last),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
                    child: Semantics(
                      button: true,
                      child: Text(
                        'Lewati',
                        style: onbBody(14, onbMuted, FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- the centre: drawing over copy ------------------------------------

  Widget _isi(double ms, bool compact) {
    final txOn = _prev >= 0;
    return LayoutBuilder(
      builder: (context, box) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (txOn)
              KeyedSubtree(
                key: ValueKey('layer-$_prev'),
                child: _layer(_prev, ms, box.maxHeight, compact, exiting: true),
              ),
            KeyedSubtree(
              key: ValueKey('layer-$_idx'),
              child: _layer(_idx, ms, box.maxHeight, compact, exiting: false),
            ),
          ],
        );
      },
    );
  }

  Widget _layer(
    int i,
    double ms,
    double height,
    bool compact, {
    required bool exiting,
  }) {
    final slide = i == _last ? introSignup : introSlides[i];
    final tx = _prev >= 0;
    final boot = !tx && !_boot.isCompleted && i == 0;
    final bootMs = _bootMs;
    final dir = _dir.toDouble();

    // What the drawing and each line of copy are doing right now.
    double artO = 1, artDx = 0, artRot = 0, artScale = 1;
    double Function(int) copyO = (_) => 1;
    double Function(int) copyDx = (_) => 0;
    double Function(int) copyDy = (_) => 0;
    if (tx && exiting) {
      final p = onbTrack(ms, 0, 280, onbIn);
      artO = 1 - p;
      artDx = -dir * 44 * p;
      artRot = -dir * 2.5 * math.pi / 180 * p;
      artScale = 1 - 0.04 * p;
      copyO = (k) => 1 - onbTrack(ms, 30.0 * k, 190, Curves.easeIn);
      copyDx = (k) => -dir * 22 * onbTrack(ms, 30.0 * k, 190, Curves.easeIn);
    } else if (tx) {
      final p = onbTrack(ms, _enterAt, 460, onbOut);
      artO = p;
      artDx = dir * 40 * (1 - p);
      copyO = (k) => onbTrack(ms, _enterAt + 110 + 65.0 * k, 440, onbOut);
      copyDx = (k) =>
          dir * 26 * (1 - onbTrack(ms, _enterAt + 110 + 65.0 * k, 440, onbOut));
    } else if (boot) {
      copyO = (k) => onbTrack(bootMs, 320 + 80.0 * k, 500, onbOut);
      copyDy = (k) => 18 * (1 - onbTrack(bootMs, 320 + 80.0 * k, 500, onbOut));
    }

    final gap = compact ? 16.0 : 18.0;
    final copyH = compact ? 127.0 : 170.0;
    final ratio = compact ? 236 / 208 : 340 / 300;
    final artH = math.min(
      compact ? 208.0 : 300.0,
      math.max(96.0, height - gap - copyH),
    );

    Widget move(Widget child, int k) => Opacity(
      opacity: copyO(k).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(copyDx(k), copyDy(k)),
        child: child,
      ),
    );

    final art = SizedBox(
      width: artH * ratio,
      height: artH,
      child: ScribbleDrawing(
        key: ValueKey('art-$i'),
        drawing: slide.drawing,
        // The draw-on starts with the new drawing's entrance.
        delay: Duration(milliseconds: !exiting && tx ? _enterAt.round() : 0),
      ),
    );

    // The tilt sits outside the movement, so the eyebrow does not wobble as
    // it settles.
    final eyebrow = SizedBox(
      height: 31,
      child: Center(
        child: Transform.rotate(
          angle: -2 * math.pi / 180,
          child: move(Text(slide.eyebrow, style: onbHand(20, onbRed)), 0),
        ),
      ),
    );
    final titleStyle1 = onbHeading(31, onbInk, height: 40 / 31);
    final titleStyle2 = onbHeading(31, onbRed, height: 40 / 31);
    final title = move(
      i == _last
          ? Text(slide.first, style: titleStyle1, textAlign: TextAlign.center)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(slide.first, style: titleStyle1),
                Text(slide.second, style: titleStyle2),
              ],
            ),
      1,
    );
    final sub = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: i == _last ? 320 : 330),
      child: move(
        Text(
          slide.sub,
          textAlign: TextAlign.center,
          style: onbBody(15, onbMuted, FontWeight.w400, 1.45),
        ),
        2,
      ),
    );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: artO.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(artDx, 0),
              child: Transform.rotate(
                angle: artRot,
                child: Transform.scale(scale: artScale, child: art),
              ),
            ),
          ),
          SizedBox(height: gap),
          SizedBox(
            height: copyH,
            // Fixed, so the drawing does not climb and fall between slides;
            // a line more than the design has (a larger font, say) spills
            // downward rather than failing to lay out.
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  eyebrow,
                  SizedBox(height: compact ? 6 : 8),
                  title,
                  SizedBox(height: compact ? 6 : 8),
                  sub,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- the foot ---------------------------------------------------------

  Widget _footer(double ms) {
    final tx = _prev >= 0;
    if (tx && _layoutTx) {
      if (ms < _enterAt) {
        // The old footer goes as one block: 220 ms, 14 down.
        final p = onbTrack(ms, 0, 220, Curves.easeIn);
        return Opacity(
          opacity: 1 - p,
          child: Transform.translate(
            offset: Offset(0, 14 * p),
            child: _prev == _last
                ? _authFooter(null)
                : _introFooter(_prev, _prev, 0),
          ),
        );
      }
      // Then the new one, child by child: 440 ms, 20 up, 150 + 55·k.
      _Move enter(int k) {
        final p = onbTrack(ms, _enterAt + 150 + 55.0 * k, 440, onbOut);
        return (o: p, dy: 20 * (1 - p));
      }

      return _idx == _last
          ? _authFooter(enter)
          : _introFooter(_idx, _idx, 0, enter: enter);
    }
    if (!tx && !_boot.isCompleted && _idx == 0) {
      final p = onbTrack(_bootMs, 520, 520, onbOut);
      return Opacity(
        opacity: p,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - p)),
          child: _introFooter(0, 0, 0),
        ),
      );
    }
    if (_idx == _last) return _authFooter(null);
    return _introFooter(_idx, tx ? _prev : _idx, tx ? ms : 0);
  }

  /// Dots over the CTA. [from] is the slide the label is leaving; in a plain
  /// slide change it crosses over: the old one lifts out (150 ms), the new
  /// drops in (260 ms).
  Widget _introFooter(
    int at,
    int from,
    double ms, {
    _Move Function(int k)? enter,
  }) {
    final showDots = at >= 1 && at <= 5;
    var label = introSlides[at].cta;
    double lo = 1, ly = 0;
    if (ms > 0 && from != at && from != _last && !_layoutTx) {
      if (ms < 150) {
        label = introSlides[from].cta;
        final p = onbTrack(ms, 0, 150, Curves.easeIn);
        lo = 1 - p;
        ly = -12 * p;
      } else {
        final p = onbTrack(ms, 150, 260, onbOut);
        lo = p;
        ly = 12 * (1 - p);
      }
    }
    Widget child(int k, Widget w) {
      if (enter == null) return w;
      final e = enter(k);
      return Opacity(
        opacity: e.o.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, e.dy), child: w),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child(
          0,
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: showDots ? 1 : 0,
            child: _Dots(active: at - 1),
          ),
        ),
        const SizedBox(height: 16),
        child(
          1,
          OnbCta(
            label: label,
            labelOpacity: lo,
            labelDy: ly,
            onTap: () => _go(_idx + 1),
          ),
        ),
      ],
    );
  }

  Widget _authFooter(_Move Function(int k)? enter) {
    final idle = _authBusy == null;
    Widget child(int k, Widget w) {
      if (enter == null) return w;
      final e = enter(k);
      return Opacity(
        opacity: e.o.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, e.dy), child: w),
      );
    }

    final apple = defaultTargetPlatform == TargetPlatform.iOS;
    final linkStyle = onbBody(11, onbRed, FontWeight.w700, 1.4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_authError != null) ...[
          Text(
            _authError!,
            textAlign: TextAlign.center,
            style: onbBody(13, onbRed, FontWeight.w600),
          ),
          const SizedBox(height: 8),
        ],
        child(
          0,
          _AuthButton(
            label: 'Lanjut dengan Google',
            loading: _authBusy == 'Google',
            onTap: idle
                ? () => _social(
                    'Google',
                    ref.read(authProvider.notifier).signInWithGoogle,
                  )
                : null,
            background: Colors.white,
            foreground: onbInk,
            border: onbLine,
            leading: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: onbLine),
              ),
              child: Text(
                'G',
                style: onbBody(14, const Color(0xFF4285F4), FontWeight.w800),
              ),
            ),
          ),
        ),
        if (apple) ...[
          const SizedBox(height: 10),
          child(
            1,
            _AuthButton(
              label: 'Lanjut dengan Apple',
              loading: _authBusy == 'Apple',
              onTap: idle
                  ? () => _social(
                      'Apple',
                      ref.read(authProvider.notifier).signInWithApple,
                    )
                  : null,
              background: onbInk,
              foreground: Colors.white,
              leading: const Icon(
                LucideIcons.apple,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        child(
          2,
          _AuthButton(
            label: 'Daftar pakai email',
            loading: false,
            onTap: idle
                ? () => _leaveTo(() => context.push(Routes.signup))
                : null,
            background: Colors.transparent,
            foreground: onbInk,
            border: onbInk,
            leading: const Icon(LucideIcons.mail, size: 18, color: onbInk),
          ),
        ),
        // The buttons' bottom 12, then the links' top 14.
        const SizedBox(height: 26),
        child(
          3,
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: idle
                  ? () => _leaveTo(() => context.push(Routes.login))
                  : null,
              child: Semantics(
                button: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Sudah punya akun?',
                      style: onbBody(14, onbMuted, FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Text('Masuk', style: onbBody(14, onbRed, FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        child(
          4,
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: idle
                  ? () => _leaveTo(() => context.go(Routes.home))
                  : null,
              child: Semantics(
                button: true,
                child: Text(
                  'Lihat-lihat dulu',
                  style: onbBody(13, onbMuted, FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        child(
          5,
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text.rich(
                TextSpan(
                  style: onbBody(11, onbMuted, FontWeight.w400, 1.4),
                  children: [
                    const TextSpan(text: 'Dengan lanjut, kamu setuju dengan '),
                    TextSpan(
                      text: 'Syarat & Ketentuan',
                      style: linkStyle,
                      recognizer: _termsTap,
                    ),
                    const TextSpan(text: ' dan '),
                    TextSpan(
                      text: 'Kebijakan Privasi',
                      style: linkStyle,
                      recognizer: _privacyTap,
                    ),
                    const TextSpan(text: ' Pokepedia.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Images the intro's drawings and chrome draw, decoded up front.
const _precache = [
  'assets/images/horizontal-logo-light.webp',
  coretanTileCream,
  'assets/images/referral/logo-coretan.webp',
  'assets/images/referral/kartu-polos/kartu-polos-bulbasaur.webp',
  'assets/images/referral/kartu-polos/kartu-polos-charmander.webp',
  'assets/images/referral/kartu-polos/kartu-polos-dragonite.webp',
  'assets/images/referral/kartu-polos/kartu-polos-eevee.webp',
  'assets/images/referral/kartu-polos/kartu-polos-gengar.webp',
  'assets/images/referral/kartu-polos/kartu-polos-jigglypuff.webp',
  'assets/images/referral/kartu-polos/kartu-polos-pikachu.webp',
  'assets/images/referral/kartu-polos/kartu-polos-poliwhirl.webp',
  'assets/images/referral/kartu-polos/kartu-polos-psyduck.webp',
  'assets/images/referral/kartu-polos/kartu-polos-snorlax.webp',
  'assets/images/referral/kartu-polos/kartu-polos-squirtle.webp',
  'assets/images/referral/kartu-polos/kartu-polos-togepi.webp',
];

/// Five dots: the active one is a 22×8 pill in red, the rest 8×8 and pale.
/// The width springs over 450 ms and the colour follows over 300.
class _Dots extends StatelessWidget {
  const _Dots({required this.active});

  final int active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: onbSpring,
              width: i == active ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == active ? onbRed : onbOff,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Google, Apple and email: 52 tall, label 15/800, icon 10 away.
class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.loading,
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.leading,
    this.border,
  });

  final String label;
  final bool loading;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final Color? border;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: StadiumBorder(
          side: border == null
              ? BorderSide.none
              : BorderSide(color: border!, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                loading
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : leading,
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: onbBody(15, foreground, FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
