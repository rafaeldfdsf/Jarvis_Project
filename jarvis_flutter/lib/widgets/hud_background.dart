import 'package:flutter/material.dart';
import 'dart:math';

class HudBackground extends StatelessWidget {
  const HudBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: HudPainter(), size: Size.infinite);
  }
}

class HudPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.05)
      ..strokeWidth = 1;

    /// GRID
    const spacing = 40.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    /// LINHAS HORIZONTAIS HUD
    final linePaint = Paint()
      ..color = Colors.blue.withOpacity(0.15)
      ..strokeWidth = 2;

    for (int i = 1; i <= 4; i++) {
      final y = size.height * (i / 5);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
