import 'dart:math';
import 'package:flutter/material.dart';

class ParticleField extends StatefulWidget {
  const ParticleField({super.key});

  @override
  State<ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<ParticleField>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;
  final Random random = Random();

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return CustomPaint(
          painter: ParticlePainter(controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class ParticlePainter extends CustomPainter {
  final double progress;
  final Random random = Random();

  ParticlePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyanAccent.withOpacity(0.3);

    for (int i = 0; i < 40; i++) {
      final dx = random.nextDouble() * size.width;
      final dy =
          (random.nextDouble() * size.height + progress * 100) % size.height;

      canvas.drawCircle(Offset(dx, dy), 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) => true;
}
