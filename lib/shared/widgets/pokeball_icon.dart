import 'package:flutter/material.dart';

/// Ports `components/icons/pokeball.tsx` as a lightweight [CustomPainter]
/// icon instead of bundling an SVG asset.
class PokeballIcon extends StatelessWidget {
  const PokeballIcon({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PokeballPainter(resolved)),
    );
  }
}

class _PokeballPainter extends CustomPainter {
  _PokeballPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - size.width * 0.05;
    final strokeWidth = size.width * 0.09;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, stroke);

    canvas.save();
    canvas.clipRect(Rect.fromCircle(center: center, radius: radius));
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      stroke,
    );
    canvas.restore();

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.28, fill);
    canvas.drawCircle(
      center,
      radius * 0.28,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant _PokeballPainter oldDelegate) =>
      oldDelegate.color != color;
}
