import 'package:flutter/material.dart';

/// Ports `components/ui/marquee.tsx` — an infinite, continuously
/// auto-scrolling horizontal strip. [duration] is the time it takes for one
/// copy of [children] to travel its own width, matching the web's
/// `--duration` CSS variable semantics.
class Marquee extends StatefulWidget {
  const Marquee({
    super.key,
    required this.children,
    this.duration = const Duration(seconds: 30),
    this.reverse = false,
    this.gap = 12,
    this.repeat = 3,
  });

  final List<Widget> children;
  final Duration duration;
  final bool reverse;
  final double gap;
  final int repeat;

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _measureKey = GlobalKey();
  double? _groupWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  void _measure(Duration _) {
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && mounted && box.hasSize) {
      setState(() => _groupWidth = box.size.width);
    }
  }

  @override
  void didUpdateWidget(covariant Marquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.children.length != widget.children.length) {
      _groupWidth = null;
      WidgetsBinding.instance.addPostFrameCallback(_measure);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Widget> _spaced() {
    final items = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      if (i > 0) items.add(SizedBox(width: widget.gap));
      items.add(widget.children[i]);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final group = Row(mainAxisSize: MainAxisSize.min, children: _spaced());

    if (_groupWidth == null) {
      // Invisible measuring pass to learn one group's natural width.
      return Opacity(
        opacity: 0,
        child: Row(key: _measureKey, mainAxisSize: MainAxisSize.min, children: _spaced()),
      );
    }

    final step = _groupWidth! + widget.gap;
    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        minWidth: 0,
        alignment: Alignment.centerLeft,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = widget.reverse ? 1 - _controller.value : _controller.value;
            return Transform.translate(
              offset: Offset(-progress * step, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.repeat, (i) {
                  return Padding(
                    padding: EdgeInsets.only(right: i == widget.repeat - 1 ? 0 : widget.gap),
                    child: group,
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }
}
