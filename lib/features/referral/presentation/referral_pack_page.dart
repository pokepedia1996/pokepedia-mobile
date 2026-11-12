import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../usecase/referral_providers.dart';
import 'referral_card_ink.dart';
import 'referral_style.dart';

/// Pack Hadiah opening (design 03, pen.dev "Referal 4a/4b v2"). The server
/// rolls the prize; the tear animation (~3.2 s) covers the
/// `open_referral_pack` call made at its start.
///
/// shortcut: the swipe-to-tear gesture is not built yet (tap or button
/// tears). Copy `pack_rip_drag.wav` back from the design package when it is.
class ReferralPackPage extends ConsumerStatefulWidget {
  const ReferralPackPage({super.key, required this.packId});

  final String packId;

  @override
  ConsumerState<ReferralPackPage> createState() => _ReferralPackPageState();
}

/// Share of the tear a drag of [dx] has done: reaches 1 at 72% of the pack's
/// width, either direction (03 §4 step 0).
@visibleForTesting
double tearProgress(double dx, double packW) =>
    (dx.abs() / (packW * 0.72)).clamp(0.0, 1.0);

enum _Phase { loading, idle, tearing, breathing, flipping, result, error }

class _ReferralPackPageState extends ConsumerState<ReferralPackPage>
    with TickerProviderStateMixin {
  var _phase = _Phase.loading;
  String? _fromUsername;
  List<ReferralTier> _tiers = const [];
  PackResult? _result;
  String? _error;
  Future<PackResult>? _opening;
  var _muted = false;
  var _skipAnimation = false;
  var _ink = const <ReferralTierKey, CardInk>{};

  CardTimeline _timelineFor(ReferralTierKey tier) => CardTimeline(
    countMs: tier == ReferralTierKey.jackpot ? 1300 : 900,
    extras: _ink[tier]?.extras.length ?? 0,
  );

  late final _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();
  late final _tear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3220),
  );
  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  // Swipe-to-tear: signed progress (sign = drag side). On release the line
  // shrinks over 260 ms and the lid bounces back over 320 ms.
  final _dragP = ValueNotifier<double>(0);
  var _dragDx = 0.0;
  var _dragLastMs = 0;
  late final _release = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  var _releaseFrom = 0.0;

  late final _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final _confetti = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  final _sfx = _Sfx();
  var _confettiCount = 0;

  // Built once: the screen stays light in dark mode (04).
  static final _lightTheme = AppTheme.light;

  // pen.dev "Close": 36 pt circle, ink at 6%. Hit area stays 48 (padded).
  static final _roundButton = IconButton.styleFrom(
    backgroundColor: const Color(0x0F1C1413),
    foregroundColor: ReferralColors.ink,
    fixedSize: const Size.square(36),
    minimumSize: const Size.square(36),
    padding: EdgeInsets.zero,
  );

  // Tear timeline (03 §4), as fractions of the 3220 ms `_tear` run.
  static const _tTearLine = Interval(0, 420 / 3220, curve: Cubic(.5, 0, .6, 1));
  static const _tShake = Interval(420 / 3220, 980 / 3220);
  static const _tLid = Interval(
    980 / 3220,
    1740 / 3220,
    curve: Cubic(.15, .75, .3, 1),
  );
  static const _tRise = Interval(
    1900 / 3220,
    2540 / 3220,
    curve: Cubic(.2, .9, .25, 1),
  );
  static const _tDrop = Interval(2540 / 3220, 1, curve: Cubic(.55, 0, .9, .45));
  static const _tCenter = Interval(
    2540 / 3220,
    1,
    curve: Cubic(.25, 1.35, .45, 1),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _skipAnimation = MediaQuery.disableAnimationsOf(context);
    if (_skipAnimation) _idle.stop();
  }

  /// Tells screen-reader users what they won; the result swaps in silently.
  void _announce(PackResult r) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${_titleFor(r.tier)} ${formatRupiah(r.amount)} masuk ke Koin Pokepedia',
      TextDirection.ltr,
    );
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _muted = prefs.getBool('referral.sound_muted') ?? false;
    } catch (_) {}
    _sfx.muted = _muted;
    // Precache so the tear never waits on a decode, and request the card's
    // fonts now so the reveal doesn't swap fonts mid-animation.
    if (mounted) {
      for (final a in ['pack-hadiah-v5', 'card-back']) {
        unawaited(
          precacheImage(AssetImage('$referralImageDir/$a.webp'), context),
        );
      }
    }
    handStyle(Colors.black);
    GoogleFonts.urbanist(fontWeight: FontWeight.w700);
    unawaited(
      GoogleFonts.pendingFonts()
          .timeout(const Duration(seconds: 3))
          .then((_) {}, onError: (_) {}),
    );
    try {
      // Fresh, not the cached provider: a pack that became ready since the
      // last fetch (e.g. opened from its notification) must not be mistaken
      // for an opened one and rolled without the tear.
      final ink = loadCardInk();
      final dashboard = await ref
          .read(referralRepositoryProvider)
          .fetchDashboard();
      _ink = await ink;
      _tiers = dashboard.tiers;
      final ready = dashboard.readyPacks.where((p) => p.id == widget.packId);
      if (ready.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _fromUsername = ready.first.fromUsername;
          _phase = _Phase.idle;
        });
        return;
      }
      // Not ready: opened (idempotent, returns the stored roll), held, void
      // or someone else's. Jump straight to the outcome.
      final result = await ref
          .read(referralRepositoryProvider)
          .openPack(widget.packId);
      if (!mounted) return;
      await _precacheResult(result);
      if (!mounted) return;
      setState(() {
        _result = result;
        _fromUsername = result.fromUsername;
        _phase = _Phase.result;
      });
      _reveal.value = 1;
      _announce(result);
    } on ReferralException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('Gagal memuat pack. Coba lagi.');
    }
  }

  Future<void> _precacheResult(PackResult r) async {
    if (!mounted) return;
    await precacheImage(
      AssetImage(characterArt(r.character)),
      context,
    ).catchError((_) {});
  }

  void _fail(String message) {
    if (!mounted) return;
    _idle.stop();
    _breath.stop();
    setState(() {
      _error = message;
      _phase = _Phase.error;
    });
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    _sfx.muted = _muted;
    try {
      await (await SharedPreferences.getInstance()).setBool(
        'referral.sound_muted',
        _muted,
      );
    } catch (_) {}
  }

  void _onDragStart() {
    if (_phase != _Phase.idle) return;
    _release.stop();
    _dragDx = 0;
    _dragLastMs = DateTime.now().millisecondsSinceEpoch;
    _sfx.startDrag();
  }

  void _onDragUpdate(double delta, double packW) {
    if (_phase != _Phase.idle) return;
    _dragDx += delta;
    final p = tearProgress(_dragDx, packW);
    _dragP.value = p * (_dragDx < 0 ? -1 : 1);
    // Louder when the finger is fast, quiet when it rests.
    final now = DateTime.now().millisecondsSinceEpoch;
    final speed = delta.abs() / math.max(1, now - _dragLastMs);
    _dragLastMs = now;
    _sfx.dragVolume((0.15 + speed / 1.2).clamp(0.15, 1.0));
    if (p >= 1) {
      _sfx.stopDrag();
      _startTear(swiped: true);
    }
  }

  void _onDragEnd() {
    if (_phase != _Phase.idle) return;
    _sfx.stopDrag();
    if (_dragP.value == 0) return;
    _releaseFrom = _dragP.value;
    _dragP.value = 0;
    _release.forward(from: 0);
  }

  Future<void> _startTear({bool swiped = false}) async {
    if (_phase != _Phase.idle) return;
    _sfx.stopDrag();
    _opening = ref.read(referralRepositoryProvider).openPack(widget.packId);
    // Refresh dashboard + Koin whatever the outcome — even if the user has
    // closed this screen by then, so the container is captured up front.
    final container = ProviderScope.containerOf(context, listen: false);
    _opening!.whenComplete(() {
      container
        ..invalidate(referralDashboardProvider)
        ..invalidate(koinBalanceProvider)
        ..invalidate(koinHistoryProvider);
    }).ignore();
    _opening!.then(_precacheResult).ignore();

    _idle.stop();
    if (_skipAnimation) {
      setState(() => _phase = _Phase.tearing);
      await _awaitResult();
      if (mounted && _result != null) {
        setState(() => _phase = _Phase.result);
        _reveal.value = 1;
        _announce(_result!);
      }
      return;
    }
    setState(() => _phase = _Phase.tearing);
    // A swipe has already drawn the line (the 420 ms step) and made the
    // sound, so the timeline resumes after it.
    final skip = swiped ? 420 : 0;
    if (!swiped) _sfx.play('pack_rip');
    _schedule(420 - skip, () {
      _sfx.play('pack_crinkle');
      HapticFeedback.lightImpact();
    });
    _schedule(980 - skip, () {
      _sfx.play('pack_flap');
      HapticFeedback.mediumImpact();
    });
    _schedule(1900 - skip, () => _sfx.play('pack_slide'));
    await _tear.forward(from: swiped ? 420 / 3220 : 0);
    if (!mounted) return;
    _dragP.value = 0;

    // Step 7: breathe for 2.6 s, longer if the server hasn't answered.
    setState(() => _phase = _Phase.breathing);
    _breath.repeat(reverse: true);
    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 2600)),
      _awaitResult(),
    ]);
    if (mounted && _phase == _Phase.breathing) await _flipCard();
  }

  /// Tap during breathing flips early, once the result is in.
  void _onCardTap() {
    if (_phase == _Phase.breathing && _result != null) _flipCard();
  }

  Future<void> _awaitResult() async {
    try {
      final r = await _opening!;
      if (mounted) setState(() => _result = r);
    } on ReferralException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('Gagal membuka pack. Coba lagi.');
    }
  }

  Future<void> _flipCard() async {
    final r = _result;
    if (r == null || _phase == _Phase.flipping) return;
    // The face shows mid-flip with its ink not yet drawn.
    final timeline = _timelineFor(r.tier);
    _reveal
      ..duration = Duration(milliseconds: timeline.total.round())
      ..value = 0;
    setState(() => _phase = _Phase.flipping);
    _breath.stop();

    if (r.tier == ReferralTierKey.langka || r.tier == ReferralTierKey.jackpot) {
      final jackpot = r.tier == ReferralTierKey.jackpot;
      _sfx.play(jackpot ? 'pack_charge_jackpot' : 'pack_charge');
      _wobble.duration = Duration(milliseconds: jackpot ? 900 : 620);
      await _wobble.forward(from: 0);
    }
    _sfx.play('pack_snap');
    _schedule(330, () {
      _sfx.play('pack_reveal_${r.tier.name}');
      _tierHaptic(r.tier);
      _confettiCount = switch (r.tier) {
        ReferralTierKey.biasa || ReferralTierKey.spesial => 40,
        ReferralTierKey.langka => 70,
        ReferralTierKey.jackpot => 110,
      };
      _confetti.forward(from: 0);
    });
    await _flip.forward(from: 0);
    if (!mounted) return;
    setState(() => _phase = _Phase.result);
    _announce(r);
    var lastTick = -1000.0;
    void tick() {
      final ms = _reveal.value * timeline.total;
      final counting = ms >= CardTimeline.countStart && ms < timeline.countEnd;
      if (counting && ms - lastTick >= 70) {
        lastTick = ms;
        _sfx.play('pack_tick', volume: 0.5);
      }
    }

    _reveal.addListener(tick);
    await _reveal.forward(from: 0);
    _reveal.removeListener(tick);
  }

  Future<void> _tierHaptic(ReferralTierKey tier) async {
    switch (tier) {
      case ReferralTierKey.biasa:
      case ReferralTierKey.spesial:
        await HapticFeedback.lightImpact();
      case ReferralTierKey.langka:
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await HapticFeedback.heavyImpact();
      case ReferralTierKey.jackpot:
        for (var i = 0; i < 3; i++) {
          await HapticFeedback.heavyImpact();
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
    }
  }

  void _schedule(int ms, VoidCallback run) {
    Future<void>.delayed(Duration(milliseconds: ms), () {
      if (mounted) run();
    });
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.referral);
    }
  }

  @override
  void dispose() {
    _dragP.dispose();
    for (final c in [
      _release,
      _idle,
      _tear,
      _breath,
      _wobble,
      _flip,
      _reveal,
      _confetti,
    ]) {
      c.dispose();
    }
    _sfx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The pack screen stays light in dark mode (04).
    return Theme(
      data: _lightTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: ReferralColors.cream,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage(
                  '$referralImageDir/pattern-energi-tile-krem.webp',
                ),
                repeat: ImageRepeat.repeat,
                scale: 2,
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(child: _body()),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _confetti,
                        builder: (_, __) => CustomPaint(
                          painter: _ConfettiPainter(
                            progress: _confetti.value,
                            count: _skipAnimation ? 0 : _confettiCount,
                            tier: _result?.tier,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    left: 8,
                    child: _phase == _Phase.result
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: Image.asset(
                              'assets/images/horizontal-logo-light.webp',
                              height: 30,
                              semanticLabel: 'Pokepedia',
                            ),
                          )
                        : IconButton(
                            tooltip: _muted
                                ? 'Nyalakan suara'
                                : 'Matikan suara',
                            onPressed: _toggleMute,
                            style: _roundButton,
                            icon: Icon(
                              _muted
                                  ? LucideIcons.volumeOff
                                  : LucideIcons.volume2,
                              size: 18,
                            ),
                          ),
                  ),
                  Positioned(
                    top: 4,
                    right: 8,
                    // Hidden while the pack opens, back once the card is
                    // fully revealed (the reveal is already at 1 for a pack
                    // opened earlier).
                    child: AnimatedBuilder(
                      animation: _reveal,
                      builder: (context, child) {
                        final busy =
                            _phase == _Phase.tearing ||
                            _phase == _Phase.breathing ||
                            _phase == _Phase.flipping ||
                            (_phase == _Phase.result && !_reveal.isCompleted);
                        return IgnorePointer(
                          ignoring: busy,
                          child: ExcludeSemantics(
                            excluding: busy,
                            child: AnimatedOpacity(
                              opacity: busy ? 0 : 1,
                              duration: const Duration(milliseconds: 200),
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: IconButton(
                        tooltip: 'Tutup',
                        onPressed: _close,
                        style: _roundButton,
                        icon: const Icon(LucideIcons.x, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.error:
        return _ErrorView(message: _error ?? '', onBack: _close);
      case _Phase.result:
        return _ResultView(
          result: _result!,
          odds: _oddsFor(_result!.tier),
          ink: _ink[_result!.tier],
          timeline: _timelineFor(_result!.tier),
          reveal: _reveal,
          onBack: _close,
        );
      case _Phase.idle:
      case _Phase.tearing:
      case _Phase.breathing:
      case _Phase.flipping:
        return LayoutBuilder(builder: (context, box) => _stage(box));
    }
  }

  // Room kept above and below the pack for the idle copy and buttons, so a
  // short screen shrinks the pack instead of covering them.
  // Header (pill, title, sub) above the pack; button + link below.
  double get _topReserve =>
      56 +
      36 +
      80 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6) +
      14;
  static const _bottomReserve = 122.0;

  double _packTop(BoxConstraints box, double packH) =>
      _topReserve + (box.maxHeight - _topReserve - _bottomReserve - packH) / 2;

  Widget _stage(BoxConstraints box) {
    // Smaller than the card so the page stays airy (prototype: max 196 wide).
    final room = box.maxHeight - _topReserve - _bottomReserve - 34;
    final packW = math
        .min(math.min(224.0, box.maxWidth * 0.54), room * 608 / 998)
        .clamp(100.0, double.infinity);
    final packH = packW * 998 / 608;
    final cardW = math.min(264.0, box.maxWidth * 0.68);
    final idle = _phase == _Phase.idle;
    final float = idle && !_skipAnimation;

    // The copy and buttons are static: kept out of the per-frame builder and
    // drawn on top so the pack never covers a button.
    return Stack(
      children: [
        Positioned.fill(
          child: _animatedStage(box, packW, packH, cardW, idle, float),
        ),
        if (idle) ..._idleCopy(),
      ],
    );
  }

  Widget _animatedStage(
    BoxConstraints box,
    double packW,
    double packH,
    double cardW,
    bool idle,
    bool float,
  ) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _idle,
        _tear,
        _breath,
        _wobble,
        _flip,
        _dragP,
        _release,
      ]),
      builder: (context, _) {
        final t = _tear.value;
        final tearLine = _tTearLine.transform(t);
        final shakeT = _tShake.transform(t);
        final shake = shakeT > 0 && shakeT < 1
            ? math.sin(shakeT * math.pi * 12) * 5 * shakeT
            : 0.0;
        final lid = _tLid.transform(t);
        final rise = _tRise.transform(t);
        final drop = _tDrop.transform(t);
        final center = _tCenter.transform(t);

        // Idle float: up 10, rotate ±2°.
        final f = float ? math.sin(_idle.value * 2 * math.pi) : 0.0;
        final floatY = float ? -5 - 5 * f : 0.0;
        final floatRot = float ? f * 2 * math.pi / 180 : 0.0;

        final packTop = _packTop(box, packH);
        // Finger-driven tear (swipe), or its release back to rest.
        double dragLine = _dragP.value, dragLid = _dragP.value;
        if (_release.isAnimating) {
          final r = _release.value;
          dragLine =
              _releaseFrom *
              (1 - Curves.easeOut.transform((r * 320 / 260).clamp(0.0, 1.0)));
          dragLid =
              _releaseFrom * (1 - const Cubic(.3, 1.6, .5, 1).transform(r));
        }
        final dragging = dragLine != 0 || dragLid != 0;
        final shadowW = packW * 160 / 204;
        final shadowH = packW * 22 / 204;
        final cardH = cardW * 384 / 264;
        // Starts narrower than the pack so it hides behind its front.
        final cardScale0 = 0.78 * packW / cardW;
        // The card is scaled about its centre, so it is placed by its centre:
        // inside the pack at first, rising 0.62 × pack height, then moving to
        // where the centred result card lands (no jump on the view swap).
        final startCenter = packTop + packH * 0.125 + cardH * cardScale0 / 2;
        final riseCenter = startCenter - packH * 0.62 * rise;
        final finalCenter = box.maxHeight / 2 + 16;
        final cardY =
            riseCenter + (finalCenter - riseCenter) * center - cardH / 2;
        final cardScale = cardScale0 + (1 - cardScale0) * center;

        final breathing = _phase == _Phase.breathing;
        final breathScale = breathing ? 1 + 0.035 * _breath.value : 1.0;
        final breathRot = breathing ? -_breath.value * math.pi / 180 : 0.0;
        final wobbleRot = _wobble.isAnimating
            ? math.sin(_wobble.value * math.pi * 16) * 4 * math.pi / 180
            : 0.0;
        final flipAngle = _flip.value * math.pi;
        final flipScale = 1 + 0.1 * math.sin(_flip.value * math.pi);
        final showCard = rise > 0;
        // The card rises out of the torn top, so the pack's front covers it
        // until the pack starts to fall away (step 6).
        final cardInFront = center > 0 || _phase != _Phase.tearing;
        final card = Positioned(
          left: (box.maxWidth - cardW) / 2,
          top: cardY,
          child: GestureDetector(
            onTap: _onCardTap,
            child: RepaintBoundary(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0009)
                  ..scaleByDouble(
                    cardScale * breathScale * flipScale,
                    cardScale * breathScale * flipScale,
                    1,
                    1,
                  )
                  ..rotateZ(breathRot + wobbleRot)
                  ..rotateY(flipAngle),
                child: flipAngle < math.pi / 2
                    ? _CardBack(
                        width: cardW,
                        glow: breathing ? _result?.tier : null,
                      )
                    : Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationY(math.pi),
                        child: _CardFace(
                          result: _result!,
                          width: cardW,
                          odds: _oddsFor(_result!.tier),
                          ink: _ink[_result!.tier],
                          timeline: _timelineFor(_result!.tier),
                          reveal: _reveal,
                        ),
                      ),
              ),
            ),
          ),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (showCard && !cardInFront) card,
            // Ground shadow: shrinks as the pack floats up, leaves with it.
            Positioned(
              left: (box.maxWidth - shadowW) / 2,
              top: packTop + packH + 6,
              child: Opacity(
                opacity: (1 - drop * 3).clamp(0, 1).toDouble(),
                child: Transform.scale(
                  scale: 1 - 0.12 * (f + 1) / 2,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Container(
                      width: shadowW,
                      height: shadowH,
                      decoration: const ShapeDecoration(
                        color: Color(0x335E1F1B),
                        shape: OvalBorder(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Pack body (below the tear line).
            Positioned(
              left: (box.maxWidth - packW) / 2 + shake,
              top: packTop + floatY + drop * box.maxHeight * 0.75,
              child: Opacity(
                opacity: (1 - drop).clamp(0, 1).toDouble(),
                child: Transform.rotate(
                  angle:
                      floatRot +
                      shake * 0.48 * math.pi / 180 +
                      drop * 12 * math.pi / 180,
                  child: GestureDetector(
                    onTap: _startTear,
                    child: RepaintBoundary(
                      child: SizedBox(
                        width: packW,
                        height: packH,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Card tucked in the pack until it rises.
                            ClipPath(
                              clipper: const _TearClipper(lid: false),
                              child: Image.asset(
                                '$referralImageDir/pack-hadiah-v5.webp',
                                width: packW,
                              ),
                            ),
                            // Lid: top 7.5%. Tilts and lifts with the finger
                            // (up to 7°, hinged at its left), then flies off.
                            Transform(
                              alignment: const FractionalOffset(0.06, 0.075),
                              transform: Matrix4.identity()
                                ..translateByDouble(
                                  0,
                                  -dragLid.abs().clamp(0.0, 1.0) *
                                      3 *
                                      (1 - lid),
                                  0,
                                  1,
                                )
                                ..rotateZ(
                                  -dragLid * 7 * math.pi / 180 * (1 - lid),
                                ),
                              child: Transform.translate(
                                offset: Offset(
                                  lid * packW * 0.7,
                                  -lid * packH * 0.42,
                                ),
                                child: Transform.rotate(
                                  angle: lid * 42 * math.pi / 180,
                                  child: Opacity(
                                    opacity: (1 - lid).clamp(0, 1).toDouble(),
                                    child: ClipPath(
                                      clipper: const _TearClipper(lid: true),
                                      child: Image.asset(
                                        '$referralImageDir/pack-hadiah-v5.webp',
                                        width: packW,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Guide: dashed line with a dot that shows the swipe.
                            if (idle && !dragging)
                              Positioned(
                                left: packW * 0.09,
                                right: packW * 0.09,
                                top: packH * 0.075 - 1,
                                height: 2,
                                child: IgnorePointer(
                                  child: _SwipeGuide(
                                    phase: _skipAnimation
                                        ? null
                                        : (_idle.value * 3200 / 2200) % 1.0,
                                  ),
                                ),
                              ),
                            // Tear line: drawn by the finger, then by the
                            // tear animation.
                            if (math.max(tearLine, dragLine.abs()) > 0)
                              Positioned(
                                left: tearLine == 0 && dragLine < 0
                                    ? packW * (1 - dragLine.abs())
                                    : 0,
                                top: packH * 0.075 - 1,
                                child: Container(
                                  width:
                                      packW *
                                      math.max(tearLine, dragLine.abs()),
                                  height: 2,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0xE6FFECBE),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Swipe zone over the top edge. Dragging 72% of
                            // the pack's width tears it; a tap tears too.
                            if (idle)
                              Positioned(
                                left: 0,
                                top: 0,
                                width: packW,
                                height: packH * 0.2,
                                child: Semantics(
                                  button: true,
                                  label: 'Robek pack',
                                  onTap: _startTear,
                                  excludeSemantics: true,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _startTear,
                                    onHorizontalDragStart: (_) =>
                                        _onDragStart(),
                                    onHorizontalDragUpdate: (d) =>
                                        _onDragUpdate(
                                          d.primaryDelta ?? 0,
                                          packW,
                                        ),
                                    onHorizontalDragEnd: (_) => _onDragEnd(),
                                    onHorizontalDragCancel: _onDragEnd,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showCard && cardInFront) card,
            if (breathing)
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: Opacity(
                  opacity: 0.4 + 0.6 * _breath.value,
                  child: Text(
                    _result == null
                        ? 'Membuka pack...'
                        : 'Ketuk kartu untuk membalik',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmSemibold(ReferralColors.muted),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  num? _oddsFor(ReferralTierKey tier) =>
      _tiers.where((t) => t.key == tier).firstOrNull?.odds;

  List<Widget> _idleCopy() => [
    Positioned(
      left: 24,
      right: 24,
      top: 56,
      child: Column(
        children: [
          if ((_fromUsername ?? '').isNotEmpty)
            _Eyebrow(
              icon: LucideIcons.partyPopper,
              text: '@$_fromUsername selesai belanja',
              background: Colors.white,
              border: ReferralColors.border,
              iconColor: ReferralColors.red,
              textColor: ReferralColors.ink,
            ),
          const SizedBox(height: 10),
          Text(
            'Pack hadiahmu datang!',
            textAlign: TextAlign.center,
            style: AppTypography.h1(ReferralColors.ink),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              'Geser jari di garis atas pack untuk merobek.',
              textAlign: TextAlign.center,
              style: _urbanist(15, FontWeight.w400, ReferralColors.muted),
            ),
          ),
        ],
      ),
    ),
    Positioned(
      left: 24,
      right: 24,
      bottom: 8,
      child: Column(
        children: [
          _Cta(
            icon: LucideIcons.sparkles,
            label: 'Robek pack',
            height: 54,
            onPressed: _startTear,
          ),
          TextButton(
            onPressed: () => showReferralOddsSheet(context, ref),
            child: Text(
              'Lihat peluang hadiah',
              style: _urbanist(13, FontWeight.w600, ReferralColors.red),
            ),
          ),
        ],
      ),
    ),
  ];
}

TextStyle _urbanist(double size, FontWeight weight, Color color) =>
    GoogleFonts.urbanist(fontSize: size, fontWeight: weight, color: color);

/// Red pill CTA with the pen.dev glow (`#AC403A40`, y8, blur 20).
class _Cta extends StatelessWidget {
  const _Cta({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.height = 52,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(999)),
        boxShadow: [
          BoxShadow(
            color: Color(0x40AC403A),
            offset: Offset(0, 8),
            blurRadius: 20,
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: ReferralColors.red,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            textStyle: _urbanist(16, FontWeight.w800, Colors.white),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      ),
    );
  }
}

/// Small rounded label with a leading icon (pen.dev "Eyebrow").
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({
    required this.icon,
    required this.text,
    required this.background,
    required this.border,
    required this.iconColor,
    required this.textColor,
  });

  final IconData icon;
  final String text;
  final Color background, border, iconColor, textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _urbanist(12, FontWeight.w700, textColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed guide along the tear line with a dot that slides left to right
/// (prototype: 2.2 s loop). [phase] null = static (reduced motion).
class _SwipeGuide extends StatelessWidget {
  const _SwipeGuide({required this.phase});

  final double? phase;

  @override
  Widget build(BuildContext context) {
    final ph = phase;
    return LayoutBuilder(
      builder: (context, box) {
        final x = ph == null
            ? 0.0
            : const Cubic(.5, 0, .3, 1).transform((ph / 0.75).clamp(0.0, 1.0));
        final o = ph == null
            ? 1.0
            : ph < .15
            ? ph / .15
            : ph < .75
            ? 1.0
            : 1 - (ph - .75) / .25;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: _DashPainter())),
            Positioned(
              left: (box.maxWidth - 14) * x,
              top: -6,
              child: Opacity(
                opacity: o.clamp(0.0, 1.0),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x59AC403A), spreadRadius: 3),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 2;
    for (var x = 0.0; x < size.width; x += 10) {
      canvas.drawLine(
        Offset(x, 1),
        Offset(math.min(x + 6, size.width), 1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

/// Jagged tear along 7.5% of the pack's height, shared by the lid and the
/// body so they fit together (prototype: 16 segments, ±1.1% amplitude).
List<Offset> tearEdge(Size s) => [
  for (var i = 0; i <= 16; i++)
    Offset(
      s.width * (0.06 + 0.88 * i / 16),
      s.height * (0.075 + (i.isOdd ? 0.011 : -0.011)),
    ),
];

class _TearClipper extends CustomClipper<Path> {
  const _TearClipper({required this.lid});

  /// True keeps the part above the tear (the lid), false the part below.
  final bool lid;

  @override
  Path getClip(Size s) {
    final edge = tearEdge(s);
    final y = s.height * 0.075;
    final path = Path();
    if (lid) {
      path
        ..moveTo(0, 0)
        ..lineTo(s.width, 0)
        ..lineTo(s.width, y);
      for (final p in edge.reversed) {
        path.lineTo(p.dx, p.dy);
      }
      path.lineTo(0, y);
    } else {
      path.moveTo(0, y);
      for (final p in edge) {
        path.lineTo(p.dx, p.dy);
      }
      path
        ..lineTo(s.width, y)
        ..lineTo(s.width, s.height)
        ..lineTo(0, s.height);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_TearClipper o) => o.lid != lid;
}

class _CardBack extends StatelessWidget {
  const _CardBack({required this.width, this.glow});

  final double width;
  final ReferralTierKey? glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.083),
        boxShadow: [
          if (glow != null)
            BoxShadow(
              color: TierStyle.of(glow!).glow.withValues(alpha: 0.6),
              blurRadius: 40,
              spreadRadius: 4,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.083),
        child: Image.asset(
          '$referralImageDir/card-back.webp',
          width: width,
          height: width * 384 / 264,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// Prize card (pen.dev "Kartu Hadiah v3"): a 264×384 face over a tier-coloured
/// edge 12 units lower, both ink-stroked, scaled by `width / 264`.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.result,
    required this.width,
    required this.timeline,
    this.odds,
    this.ink,
    this.reveal,
  });

  final PackResult result;
  final double width;
  final CardTimeline timeline;

  /// The tier's percent from the server; hidden when unknown.
  final num? odds;

  /// Ring, underline and sparkles; null draws the card without them.
  final CardInk? ink;

  /// 0→1 over [timeline]; null shows it settled.
  final Animation<double>? reveal;

  @override
  Widget build(BuildContext context) {
    final s = TierStyle.of(result.tier);
    final u = width / 264;
    final radius = BorderRadius.circular(20 * u);
    final border = Border.all(color: ReferralColors.ink, width: 3.5 * u);

    Widget paint(double ms) => CustomPaint(
      painter: CardFacePainter(
        tier: result.tier,
        amount: result.amount,
        odds: odds,
        ink: ink,
        timeline: timeline,
        ms: ms,
      ),
    );

    // Read as one label, not as a count-up of digits.
    return Semantics(
      label:
          '${result.tier.label}, ${formatRupiah(result.amount)}, ${characterName(result.character)}',
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: 396 * u,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 12 * u,
              height: 384 * u,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: s.cardEdge,
                  borderRadius: radius,
                  border: border,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x335E1F1B),
                      offset: Offset(0, 14),
                      blurRadius: 28,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 384 * u,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: s.cardBg,
                  borderRadius: radius,
                  border: border,
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 18 * u,
                      top: 18 * u,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12 * u),
                        child: Image.asset(
                          characterArt(result.character),
                          width: 228 * u,
                          height: 226 * u,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              SizedBox(width: 228 * u, height: 226 * u),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: reveal == null
                          ? paint(double.infinity)
                          : AnimatedBuilder(
                              animation: reveal!,
                              builder: (_, __) =>
                                  paint(reveal!.value * timeline.total),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.result,
    required this.odds,
    required this.ink,
    required this.timeline,
    required this.reveal,
    required this.onBack,
  });

  final PackResult result;
  final num? odds;
  final CardInk? ink;
  final CardTimeline timeline;
  final Animation<double> reveal;
  final VoidCallback onBack;

  /// Hidden until the count-up ends — and untappable/unread while hidden,
  /// not just invisible.
  Widget _afterCount(Widget child) => AnimatedBuilder(
    animation: reveal,
    builder: (_, child) {
      final done = reveal.value * timeline.total >= timeline.countEnd;
      return IgnorePointer(
        ignoring: !done,
        child: ExcludeSemantics(
          excluding: !done,
          child: AnimatedOpacity(
            opacity: done ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: child,
          ),
        ),
      );
    },
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final width = math.min(264.0, MediaQuery.sizeOf(context).width * 0.68);
    // Body centred between the top bar and the pinned button (pen.dev 4b);
    // scrolls instead of overflowing on short screens or large text.
    return CustomScrollView(
      // A fixed screen: it must not move under the finger. The content is
      // sized to fit; only a very large text size could push it off.
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _Eyebrow(
                          icon: LucideIcons.gift,
                          text: 'Hadiah Ajak Teman Pokepedia',
                          background: ReferralColors.red,
                          border: ReferralColors.red,
                          iconColor: Colors.white,
                          textColor: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _titleFor(result.tier),
                          textAlign: TextAlign.center,
                          style: AppTypography.h1(
                            ReferralColors.ink,
                          ).copyWith(fontSize: 28),
                        ),
                        const SizedBox(height: 14),
                        _CardFace(
                          result: result,
                          width: width,
                          odds: odds,
                          ink: ink,
                          timeline: timeline,
                          reveal: reveal,
                        ),
                        const SizedBox(height: 14),
                        _afterCount(
                          Column(
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    const WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: Icon(
                                          LucideIcons.coins,
                                          size: 16,
                                          color: ReferralColors.red,
                                        ),
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          '${formatRupiah(result.amount)} masuk ke Koin Pokepedia',
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                                style: _urbanist(
                                  15,
                                  FontWeight.w800,
                                  ReferralColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Bisa dipakai belanja di Pokepedia, berlaku 12 bulan.',
                                textAlign: TextAlign.center,
                                style: _urbanist(
                                  13,
                                  FontWeight.w600,
                                  ReferralColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _afterCount(
                  _Cta(
                    icon: LucideIcons.arrowLeft,
                    label: 'Kembali ke Ajak Teman',
                    onPressed: onBack,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('$referralImageDir/pack-hadiah-v5.webp', width: 120),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.h3(ReferralColors.ink),
            ),
            const SizedBox(height: 24),
            _Cta(
              icon: LucideIcons.arrowLeft,
              label: 'Kembali ke Ajak Teman',
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Lihat peluang hadiah" (03 §5): odds from the server, Jackpot first.
Future<void> showReferralOddsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ReferralColors.sheetBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final odds = ref.watch(referralOddsProvider);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Peluang hadiah',
                style: AppTypography.h3(ReferralColors.ink),
              ),
              const SizedBox(height: 6),
              Text(
                'Tiap pack berisi 1 hadiah Koin Pokepedia. 1 Koin = Rp1, bisa dipakai belanja di Pokepedia, '
                'berlaku 12 bulan sejak didapat, dan tidak bisa ditarik ke rekening. Karakter di kartu diacak dari tiap tingkatan.',
                style: AppTypography.bodySm(ReferralColors.muted),
              ),
              const SizedBox(height: 8),
              odds.when(
                data: (tiers) => Column(
                  children: [
                    for (final t in tiers) ...[
                      const Divider(height: 1, color: ReferralColors.codeLine),
                      TierOddsRow(t, showPool: true, dark: ReferralColors.ink),
                    ],
                  ],
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Text(
                  'Gagal memuat peluang.',
                  style: AppTypography.bodySm(ReferralColors.muted),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// One reusable player per effect (three for the rapid count-up ticks),
/// loaded once per screen. A fresh player per sound leaked native handles on
/// Android and cost platform round-trips per tick on iOS. Ambient session:
/// respects the silent switch and doesn't stop the user's music.
class _Sfx {
  _Sfx() {
    final ctx = AudioContextConfig(respectSilence: true).build();
    for (final name in _effects) {
      _pool[name] = [
        for (var i = 0; i < (name == 'pack_tick' ? 3 : 1); i++)
          _load(name, ctx),
      ];
    }
  }

  static const _effects = [
    'pack_rip',
    'pack_rip_drag',
    'pack_crinkle',
    'pack_flap',
    'pack_slide',
    'pack_snap',
    'pack_charge',
    'pack_charge_jackpot',
    'pack_tick',
    'pack_reveal_biasa',
    'pack_reveal_spesial',
    'pack_reveal_langka',
    'pack_reveal_jackpot',
  ];

  var muted = false;
  final _pool = <String, List<AudioPlayer>>{};
  final _next = <String, int>{};

  static AudioPlayer _load(String name, AudioContext ctx) {
    final player = AudioPlayer();
    unawaited(() async {
      try {
        await player.setAudioContext(ctx);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource('sounds/$name.wav'));
      } catch (e) {
        debugPrint('[referral] sound $name failed to load: $e');
      }
    }());
    return player;
  }

  Future<void> play(String name, {double volume = 1}) async {
    final players = _pool[name];
    if (muted || players == null) return;
    final i = _next[name] ?? 0;
    _next[name] = (i + 1) % players.length;
    final player = players[i];
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.resume();
    } catch (e) {
      debugPrint('[referral] sound $name failed: $e');
    }
  }

  /// Looks like ripping while the finger drags the tear line.
  void startDrag() => play('pack_rip_drag', volume: 0.3);

  void dragVolume(double v) {
    final p = _pool['pack_rip_drag']?.first;
    if (muted || p == null) return;
    p.setVolume(v).catchError((Object _) {});
  }

  void stopDrag() {
    final p = _pool['pack_rip_drag']?.first;
    p?.stop().catchError((Object _) {});
  }

  void dispose() {
    for (final players in _pool.values) {
      for (final p in players) {
        p.dispose();
      }
    }
    _pool.clear();
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.count, this.tier});

  final double progress;
  final int count;
  final ReferralTierKey? tier;

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0 || progress == 0 || progress == 1) return;
    final rnd = math.Random(7);
    final colors = [
      ReferralColors.red,
      ReferralColors.pillGold,
      if (tier != null) TierStyle.of(tier!).bar,
      const Color(0xFF5D86D6),
    ];
    final paint = Paint();
    final origin = Offset(size.width / 2, size.height * 0.45);
    for (var i = 0; i < count; i++) {
      final angle = rnd.nextDouble() * 2 * math.pi;
      final speed = 180 + rnd.nextDouble() * 260;
      final t = progress;
      final dx = math.cos(angle) * speed * t;
      final dy = math.sin(angle) * speed * t + 420 * t * t;
      paint.color = colors[i % colors.length].withValues(alpha: 1 - t);
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(t * 8 + i);
      canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.progress != progress || old.count != count;
}

String _titleFor(ReferralTierKey tier) => switch (tier) {
  ReferralTierKey.biasa => 'Lumayan, dapat yang Biasa!',
  ReferralTierKey.spesial => 'Asik, dapat Spesial!',
  ReferralTierKey.langka => 'Wah, dapat yang Langka!',
  ReferralTierKey.jackpot => 'JACKPOT! Hoki banget!',
};
