import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';

/// Ports `components/ui/card-swap.tsx` — a stack of cards where the front
/// card periodically drops away and cycles to the back, promoting the rest.
/// Simplified from the web's GSAP timeline to a single elastic
/// [AnimationController] driving the same slot choreography.
class CardSwap extends StatefulWidget {
  const CardSwap({
    super.key,
    required this.imageUrls,
    this.cardWidth = 220,
    this.cardHeight = 280,
    this.cardDistance = 34,
    this.verticalDistance = 40,
    this.delay = const Duration(milliseconds: 4500),
  });

  final List<String> imageUrls;
  final double cardWidth;
  final double cardHeight;
  final double cardDistance;
  final double verticalDistance;
  final Duration delay;

  @override
  State<CardSwap> createState() => _CardSwapState();
}

class _CardSwapState extends State<CardSwap> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<int> _order;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _order = List.generate(widget.imageUrls.length, (i) => i);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _order = [..._order.skip(1), _order.first];
            _controller.value = 0;
          });
        }
      });
    if (widget.imageUrls.length > 1) {
      _timer = Timer.periodic(widget.delay, (_) => _controller.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Offset _slotOffset(int depth) =>
      Offset(depth * widget.cardDistance, -depth * widget.verticalDistance);

  double _slotScale(int depth) => 1 - depth * 0.06;

  double _slotRotation(int depth) => depth == 0 ? 0 : -0.035 * depth;

  @override
  Widget build(BuildContext context) {
    final total = _order.length;
    return SizedBox(
      width: widget.cardWidth + widget.cardDistance * (total - 1),
      height: widget.cardHeight + widget.verticalDistance * (total - 1) + 60,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.elasticOut.transform(_controller.value);
          final cards = <(int zIndex, Positioned widget)>[];

          for (var pos = 0; pos < total; pos++) {
            final index = _order[pos];
            final isFront = pos == 0;

            Offset offset;
            double scale;
            double rotation;
            int zIndex;

            if (isFront) {
              final start = _slotOffset(0);
              final end = _slotOffset(total - 1);
              final dip = math.sin(_controller.value * math.pi) * 90;
              offset = Offset.lerp(start, end, t)! + Offset(0, dip);
              scale = _slotScale(0) + (_slotScale(total - 1) - _slotScale(0)) * t;
              rotation = _slotRotation(0) + (_slotRotation(total - 1) - _slotRotation(0)) * t;
              zIndex = t < 0.5 ? total : 0;
            } else {
              final start = _slotOffset(pos);
              final end = _slotOffset(pos - 1);
              offset = Offset.lerp(start, end, t)!;
              scale = _slotScale(pos) + (_slotScale(pos - 1) - _slotScale(pos)) * t;
              rotation = _slotRotation(pos) + (_slotRotation(pos - 1) - _slotRotation(pos)) * t;
              zIndex = total - pos + 1;
            }

            cards.add((
              zIndex,
              Positioned(
                key: ValueKey(index),
                left: offset.dx,
                top: offset.dy + widget.verticalDistance * (total - 1) + 30,
                child: _DeckCard(
                  scale: scale,
                  rotation: rotation,
                  width: widget.cardWidth,
                  height: widget.cardHeight,
                  imageUrl: widget.imageUrls[index],
                ),
              ),
            ));
          }

          cards.sort((a, b) => a.$1.compareTo(b.$1));

          return Stack(
            clipBehavior: Clip.none,
            children: [for (final c in cards) c.$2],
          );
        },
      ),
    );
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.scale,
    required this.rotation,
    required this.width,
    required this.height,
    required this.imageUrl,
  });

  final double scale,
      rotation,
      width,
      height;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 10)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
          ),
        ),
      ),
    );
  }
}
