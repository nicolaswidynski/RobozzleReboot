import 'package:flutter/material.dart';

/// Paints a dashed rounded-rectangle border around [child]. Used for empty
/// program slots so they read as placeholders rather than filled cells,
/// mirroring the original game's dotted slot styling.
class DashedRoundedBorder extends StatelessWidget {
  final double radius;
  final Color color;
  final double strokeWidth;
  final Widget? child;

  const DashedRoundedBorder({
    super.key,
    required this.radius,
    required this.color,
    this.strokeWidth = 1.5,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(radius: radius, color: color, strokeWidth: strokeWidth),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final double radius;
  final Color color;
  final double strokeWidth;

  _DashedRRectPainter({required this.radius, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    const dashWidth = 4.0;
    const dashGap = 3.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}
