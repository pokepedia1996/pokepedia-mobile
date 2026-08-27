import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Flies [child] from the widget behind [from] to the one behind [to] — the
/// "it went into the cart" confirmation that plays after a successful
/// add-to-cart.
///
/// Purely decorative: if either end can't be located (the page scrolled the
/// artwork off screen, the app bar has no cart button) it returns without
/// drawing anything rather than failing the add the buyer already made.
///
/// Awaiting it is optional — the returned future completes when the flight
/// lands and the overlay is torn down.
Future<void> flyToCart({
  required BuildContext context,
  required GlobalKey from,
  required GlobalKey to,
  required Widget child,
  Duration duration = const Duration(milliseconds: 620),
}) async {
  final overlay = Overlay.maybeOf(context);
  final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
  if (overlay == null || overlayBox == null) return;

  final start = _rectOf(from, overlayBox);
  final end = _rectOf(to, overlayBox);
  if (start == null || end == null) return;

  late final OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    // `mounted` guards the case where the overlay itself went away with the
    // page — removing an entry that is no longer in a tree asserts.
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _CartFlight(
      from: start,
      to: end,
      duration: duration,
      onDone: remove,
      child: child,
    ),
  );
  overlay.insert(entry);

  // The flight owns its own removal so a page disposed mid-animation still
  // cleans up; this wait only mirrors it back to the caller.
  await Future<void>.delayed(duration + const Duration(milliseconds: 40));
  remove();
}

/// Where [key]'s widget sits in the overlay's coordinate space.
Rect? _rectOf(GlobalKey key, RenderBox overlayBox) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
}

class _CartFlight extends StatefulWidget {
  const _CartFlight({
    required this.from,
    required this.to,
    required this.duration,
    required this.onDone,
    required this.child,
  });

  final Rect from;
  final Rect to;
  final Duration duration;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_CartFlight> createState() => _CartFlightState();
}

class _CartFlightState extends State<_CartFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Quadratic bezier — the control point pulls the path sideways so the
  /// card arcs into the cart instead of sliding along a straight line.
  Offset _pointAt(double t) {
    final start = widget.from.center;
    final end = widget.to.center;
    final control = Offset(end.dx, start.dy);
    final inverse = 1 - t;
    return start * (inverse * inverse) +
        control * (2 * inverse * t) +
        end * (t * t);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: IgnorePointer(child: widget.child),
      builder: (context, child) {
        final t = Curves.easeInOutCubic.transform(_controller.value);
        final center = _pointAt(t);
        // Shrinks towards the size of the icon it is landing on.
        final scale = lerpDouble(1, 0.16, Curves.easeInCubic.transform(t))!;
        final width = widget.from.width * scale;
        final height = widget.from.height * scale;
        // Only the last stretch fades, so the card stays readable for most
        // of the trip.
        final opacity = t < 0.8 ? 1.0 : (1 - (t - 0.8) / 0.2).clamp(0.0, 1.0);

        return Positioned(
          left: center.dx - width / 2,
          top: center.dy - height / 2,
          width: width,
          height: height,
          child: Opacity(opacity: opacity, child: child),
        );
      },
    );
  }
}
