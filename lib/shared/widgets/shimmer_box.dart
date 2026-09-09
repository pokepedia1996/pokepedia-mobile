import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// One clock for every shimmer on screen.
///
/// A grid of loading cards is forty placeholders at once; forty animation
/// controllers ticking in step is forty times the bookkeeping for one
/// visible effect. They share this instead, and it only runs while something
/// is listening.
class _ShimmerClock extends ChangeNotifier {
  _ShimmerClock._();

  static final instance = _ShimmerClock._();

  /// How long one sweep takes, end to end.
  static const _period = Duration(milliseconds: 1400);

  Ticker? _ticker;

  /// Where in the sweep we are, 0 → 1.
  double progress = 0;

  void _tick(Duration elapsed) {
    progress =
        (elapsed.inMilliseconds % _period.inMilliseconds) /
        _period.inMilliseconds;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _ticker ??= Ticker(_tick)..start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _ticker?.dispose();
      _ticker = null;
      progress = 0;
    }
  }
}

/// Slides the highlight across the box.
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.progress);

  final double progress;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    // From one width off the left to one width off the right, so the band
    // enters and leaves rather than appearing mid-box.
    return Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
  }
}

/// A placeholder that shimmers while the thing it stands in for loads.
///
/// Used where an image has been asked for but has not arrived. It says
/// "coming" without drawing anything the reader might mistake for content —
/// which a card back does: at a glance it looks like a card that simply has
/// no art, and it costs a decode of the bundled asset for every tile on
/// screen.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({super.key, this.borderRadius});

  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.secondary;
    // The highlight is the surface colour rather than white: on a dark theme
    // a white band reads as a flash, not a sheen.
    final highlight = Color.alphaBlend(
      theme.colorScheme.surface.withValues(alpha: 0.65),
      base,
    );

    return AnimatedBuilder(
      animation: _ShimmerClock.instance,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            colors: [base, highlight, base],
            stops: const [0.35, 0.5, 0.65],
            transform: _SweepTransform(_ShimmerClock.instance.progress),
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
