import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/design_palette.dart';
import 'scribble_drawing.dart';
import 'setup_kit.dart';

/// The pieces of the hand-drawn ("coretan") screens — cream and pattern,
/// handwritten eyebrows, sticker cards with hard shadows, the dark pill —
/// and the motion they move with.
///
/// Light only, like the designs: a screen built from these sits on cream
/// whatever the app's theme, and locks itself to the light theme so the
/// [DesignPalette] it reads is the designs' own.

/// Most things that enter.
const coretanOut = Cubic(.2, .8, .2, 1);

/// Page pushes.
const coretanPush = Cubic(.22, .8, .2, 1);

/// Cards and coupons popping in.
const coretanPop = Cubic(.3, .7, .3, 1);

/// A small overshoot: chips pressed, an avatar letter changing.
const coretanBounce = Cubic(.3, 1.5, .5, 1);

/// The pattern tiles, at the size the designs repeat them (259×225 from a
/// 778×674 file).
const coretanTileCream = 'assets/images/referral/pattern-energi-tile-krem.webp';
const coretanTileRed = 'assets/images/referral/pattern-energi-tile-merah.webp';

/// Whether the OS asked for less motion.
bool coretanReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Cream with the energy pattern over it — the floor of every step.
class CoretanBackground extends StatelessWidget {
  const CoretanBackground({
    super.key,
    required this.child,
    this.tile = coretanTileCream,
    this.color = AppColors.onbCream,
    this.borderRadius,
  });

  final Widget child;
  final String tile;
  final Color color;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        image: DecorationImage(
          image: AssetImage(tile),
          repeat: ImageRepeat.repeat,
          // 778 px drawn as 259 pt.
          scale: 3,
          alignment: Alignment.topLeft,
        ),
      ),
      child: child,
    );
  }
}

/// Back, a segment per step, and "2/4" in hand.
///
/// Built to stay on screen while the steps change under it: a new [step]
/// fills its segment from the left (600 ms) — or empties the one stepped
/// back from — and the label crossfades, rather than the whole bar being
/// drawn again. The first step's segment fills as the flow opens.
class CoretanStepHeader extends StatelessWidget {
  const CoretanStepHeader({
    super.key,
    required this.step,
    required this.onBack,
    this.total = 4,
  });

  /// 1-based, as the label reads.
  final int step;
  final int total;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final still = coretanReduceMotion(context);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          CoretanIconButton(
            icon: LucideIcons.arrowLeft,
            label: 'Kembali',
            onPressed: onBack,
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 1; i <= total; i++) ...[
                    if (i > 1) const SizedBox(width: 6),
                    Container(
                      width: 34,
                      height: 8,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.onbOff,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      // Starts empty, so the first segment fills as the
                      // flow opens; after that each change animates from
                      // wherever the segment is.
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: i <= step ? 1 : 0),
                        duration: still
                            ? Duration.zero
                            : const Duration(milliseconds: 600),
                        curve: coretanOut,
                        builder: (context, fill, _) => FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: fill,
                          child: ColoredBox(color: palette.brand),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerRight,
                children: [...previous, ?current],
              ),
              child: Text(
                '$step/$total',
                key: ValueKey(step),
                textAlign: TextAlign.right,
                style: AppTypography.hand(palette.ink, size: 19),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The round ghost button the designs put back and close in.
class CoretanIconButton extends StatelessWidget {
  const CoretanIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;

  /// What a screen reader says; the button has no text.
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Material(
      color: palette.ink.withValues(alpha: 0.05),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 38,
          child: Icon(icon, size: 20, color: palette.ink, semanticLabel: label),
        ),
      ),
    );
  }
}

/// "langkah 2 dari 4" — handwritten, in red, a little crooked.
class CoretanEyebrow extends StatelessWidget {
  const CoretanEyebrow(this.text, {super.key, this.size = 20, this.center});

  final String text;
  final double size;
  final bool? center;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Transform.rotate(
      angle: -2 * math.pi / 180,
      alignment: center == true ? Alignment.center : Alignment.centerLeft,
      child: Text(
        text,
        textAlign: center == true ? TextAlign.center : TextAlign.start,
        style: AppTypography.hand(palette.brand, size: size),
      ),
    );
  }
}

/// A handwritten line under a field that changes with what was typed: a
/// new text fades in from 4 pt above.
class CoretanHint extends StatelessWidget {
  const CoretanHint(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.2),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Text(
        text,
        key: ValueKey('$text$color'),
        style: AppTypography.hand(color, size: 18),
      ),
    );
  }
}

/// The dark pill at the foot of a step.
class CoretanButton extends StatelessWidget {
  const CoretanButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.leading,
    this.trailing = LucideIcons.arrowRight,
  });

  final String label;
  final VoidCallback? onPressed;

  /// A spinner in place of the label, while the press is being answered.
  final bool busy;
  final IconData? leading;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final fg = palette.ctaForeground;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: palette.ctaBackground,
        foregroundColor: fg,
        disabledBackgroundColor: busy
            ? palette.ctaBackground
            : AppColors.onbDisabled,
        disabledForegroundColor: fg,
        minimumSize: Size.fromHeight(setupSize(60)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const StadiumBorder(),
      ),
      child: busy
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  Icon(leading, size: 18, color: fg),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: setupText(18, fg, FontWeight.w700),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  Icon(trailing, size: 18, color: fg),
                ],
              ],
            ),
    );
  }
}

/// A white card on cream. [selected] turns it into a sticker: an ink
/// outline, a hard shadow, and a lift of a point up and left.
class CoretanCard extends StatelessWidget {
  const CoretanCard({
    super.key,
    required this.child,
    this.selected = false,
    this.onTap,
    this.radius = 20,
    this.color,
    this.borderColor,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final shape = BorderRadius.circular(radius);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: coretanOut,
      transform: Matrix4.translationValues(
        selected ? -1 : 0,
        selected ? -1 : 0,
        0,
      ),
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: shape,
        border: Border.all(
          color: selected ? palette.ink : borderColor ?? AppColors.onbLine,
          width: selected ? 2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: selected ? palette.ink : Colors.transparent,
            offset: const Offset(3, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A small rounded label in the designs' yellow: "Populer", "Otomatis".
class CoretanPill extends StatelessWidget {
  const CoretanPill({
    super.key,
    required this.label,
    this.icon,
    this.background = const Color(0xFFFDF1D8),
    this.foreground = const Color(0xFF8A5A00),
  });

  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(label, style: setupText(13, foreground, FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Enters after [delay]: fades in and rises [rise] points.
///
/// The blocks of a step pass `200 + 45·k` ms, so they arrive one after the
/// other. With reduced motion it is simply there.
class CoretanReveal extends StatefulWidget {
  const CoretanReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 480),
    this.rise = 14,
  });

  /// The delay for the [index]th block of a step.
  CoretanReveal.at(int index, {Key? key, required Widget child})
    : this(
        key: key,
        delay: Duration(milliseconds: 200 + 45 * index),
        child: child,
      );

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double rise;

  @override
  State<CoretanReveal> createState() => _CoretanRevealState();
}

class _CoretanRevealState extends State<CoretanReveal>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration);
  late final _t = CurvedAnimation(parent: _c, curve: coretanOut);
  Timer? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted || _start != null) return;
    if (coretanReduceMotion(context)) {
      _c.value = 1;
      return;
    }
    _start = Timer(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, widget.rise * (1 - _t.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Grows from small to a little past full size and back, each time [value]
/// changes — a count ticking over, a name being typed.
class CoretanPop extends StatefulWidget {
  const CoretanPop({
    super.key,
    required this.value,
    required this.child,
    this.from = 0.92,
    this.duration = const Duration(milliseconds: 260),
  });

  final Object? value;
  final Widget child;
  final double from;
  final Duration duration;

  @override
  State<CoretanPop> createState() => _CoretanPopState();
}

class _CoretanPopState extends State<CoretanPop>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  @override
  void didUpdateWidget(CoretanPop old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !coretanReduceMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(
        begin: widget.from,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _c, curve: coretanBounce)),
      child: widget.child,
    );
  }
}

/// A box ticked in pen: the scribbled outline, and a red tick drawn in when
/// [checked]. [size] is the box's side.
class CoretanCheckbox extends StatelessWidget {
  const CoretanCheckbox({
    super.key,
    required this.checked,
    this.size = 26,
    this.delay = Duration.zero,
  });

  final bool checked;
  final double size;

  /// Before the tick starts drawing — for a list ticking in one by one.
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ScribbleDrawing(
        // A new drawing each time the state flips, so the tick draws in.
        key: ValueKey(checked),
        drawing: checked ? 'toko_cbOn' : 'toko_cbOff',
        size: size,
        stepMs: 40,
        delay: delay,
        idle: false,
      ),
    );
  }
}

/// The round tick at the end of a pickable card: an empty pen ring, or a
/// red one with a tick drawn in.
class CoretanRadio extends StatelessWidget {
  const CoretanRadio({super.key, required this.selected, this.size = 30});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ScribbleDrawing(
      key: ValueKey(selected),
      drawing: selected ? 'icon_chkOn' : 'icon_chkOff',
      size: size,
      stepMs: 40,
      idle: false,
    );
  }
}

/// One step's content giving way to the next on the same page, for an
/// [AnimatedSwitcher] whose duration is [coretanStepDuration].
///
/// The page — its paper and its header — stays where it is. The leaving
/// content fades out in the first 40% while drifting a little the way the
/// flow is going; the arriving content slides in from a little way off on
/// the other side and fades up after a short beat, so the two never read as
/// one muddle. Its blocks then arrive one by one ([CoretanReveal]). With
/// reduced motion it is a plain crossfade.
const coretanStepDuration = Duration(milliseconds: 420);

Widget coretanStepTransition({
  required BuildContext context,
  required Widget child,
  required Animation<double> animation,
  required bool incoming,
  required bool forward,
}) {
  if (coretanReduceMotion(context)) {
    return IgnorePointer(
      ignoring: !incoming,
      child: FadeTransition(opacity: animation, child: child),
    );
  }
  final direction = forward ? 1.0 : -1.0;
  // The switcher runs a leaving child's animation from 1 back to 0, so its
  // curve is read backwards: Interval(.6, 1) has it gone by 40% of the way.
  final fade = CurvedAnimation(
    parent: animation,
    curve: incoming
        ? const Interval(.3, 1, curve: coretanOut)
        : const Interval(.6, 1, curve: Curves.easeOut),
  );
  final slide = CurvedAnimation(
    parent: animation,
    curve: incoming ? coretanOut : Curves.easeIn,
  );
  return IgnorePointer(
    ignoring: !incoming,
    child: FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween(
          begin: Offset((incoming ? .08 : -.05) * direction, 0),
          end: Offset.zero,
        ).animate(slide),
        child: child,
      ),
    ),
  );
}

/// Paper confetti falling over the finished screen: 46 bits — squares and
/// dots in red, yellow, blue, green, pink and ink — each falling for 1.6–3 s
/// and turning as it goes. Not drawn at all with reduced motion.
class CoretanConfetti extends StatefulWidget {
  const CoretanConfetti({
    super.key,
    this.delay = const Duration(milliseconds: 520),
    this.count = 46,
  });

  final Duration delay;
  final int count;

  @override
  State<CoretanConfetti> createState() => _CoretanConfettiState();
}

class _CoretanConfettiState extends State<CoretanConfetti>
    with SingleTickerProviderStateMixin {
  // Made in initState, not lazily: with reduced motion nothing else
  // touches it, and a controller first made in dispose() fails.
  late final AnimationController _c;
  late final List<_Bit> _bits;
  Timer? _start;
  bool _off = false;

  static const _colors = [
    Color(0xFFAC403A),
    Color(0xFFF4B63F),
    Color(0xFF4F86C6),
    Color(0xFF2E9E57),
    Color(0xFFF2A0B5),
    Color(0xFF1C1413),
  ];

  @override
  void initState() {
    super.initState();
    // The slowest bit falls for 3 s after a start of up to 0.6 s.
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    final rng = math.Random(7);
    _bits = [
      for (var i = 0; i < widget.count; i++)
        _Bit(
          x: rng.nextDouble(),
          start: rng.nextDouble() * 0.6,
          fall: 1.6 + rng.nextDouble() * 1.4,
          drift: (rng.nextDouble() - .5) * 0.12,
          spin: (rng.nextDouble() - .5) * 6 * math.pi,
          dot: rng.nextDouble() < .35,
          color: _colors[i % _colors.length],
        ),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _off = coretanReduceMotion(context);
    if (_off || _start != null) return;
    _start = Timer(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_off) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ConfettiPainter(_c, _bits),
      ),
    );
  }
}

class _Bit {
  const _Bit({
    required this.x,
    required this.start,
    required this.fall,
    required this.drift,
    required this.spin,
    required this.dot,
    required this.color,
  });

  /// Across the width, 0–1.
  final double x;

  /// Seconds after the shower starts.
  final double start;

  /// Seconds to fall the height.
  final double fall;

  /// Sideways over the fall, as a share of the width.
  final double drift;

  /// Radians turned over the fall.
  final double spin;
  final bool dot;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.clock, this.bits) : super(repaint: clock);

  final AnimationController clock;
  final List<_Bit> bits;

  @override
  void paint(Canvas canvas, Size size) {
    if (!clock.isAnimating) return;
    final seconds = clock.value * 3.6;
    final paint = Paint();
    for (final bit in bits) {
      final p = (seconds - bit.start) / bit.fall;
      if (p <= 0 || p >= 1) continue;
      final y = -20 + (size.height + 40) * Curves.easeIn.transform(p);
      final x = size.width * (bit.x + bit.drift * p);
      paint.color = bit.color.withValues(alpha: p > .85 ? (1 - p) / .15 : 1);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(bit.spin * p);
      if (bit.dot) {
        canvas.drawCircle(Offset.zero, 4, paint);
      } else {
        canvas.drawRect(const Rect.fromLTWH(-4, -6.5, 8, 13), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
