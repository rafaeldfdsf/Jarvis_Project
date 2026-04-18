import 'dart:math';
import 'package:flutter/material.dart';
import '../models/assistant_state.dart';

/// Widget da esfera Jarvis.
/// Esta esfera reage ao estado do assistente:
/// - idle
/// - listening
/// - thinking
/// - speaking
class JarvisOrb extends StatefulWidget {
  final AssistantState state;
  final double size;
  final String assistantName;

  const JarvisOrb({
    super.key,
    required this.state,
    required this.assistantName,
    this.size = 230,
  });

  @override
  State<JarvisOrb> createState() => _JarvisOrbState();
}

class _JarvisOrbState extends State<JarvisOrb> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();

    /// Controla a pulsação principal.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    /// Controla a rotação dos anéis.
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    /// Controla o brilho externo.
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  /// Cor principal da orb consoante o estado.
  Color _mainColor() {
    switch (widget.state) {
      case AssistantState.idle:
        return const Color(0xFF59D8FF);
      case AssistantState.listening:
        return const Color(0xFF00E5FF);
      case AssistantState.thinking:
        return const Color(0xFF7C4DFF);
      case AssistantState.speaking:
        return const Color(0xFF00B0FF);
    }
  }

  /// Texto auxiliar no centro.
  String _label() {
    switch (widget.state) {
      case AssistantState.idle:
        return widget.assistantName.toUpperCase();
      case AssistantState.listening:
        return "A OUVIR";
      case AssistantState.thinking:
        return "A PENSAR";
      case AssistantState.speaking:
        return "A FALAR";
    }
  }

  /// Intensidade da pulsação.
  double _pulseStrength() {
    switch (widget.state) {
      case AssistantState.idle:
        return 0.04;
      case AssistantState.listening:
        return 0.10;
      case AssistantState.thinking:
        return 0.07;
      case AssistantState.speaking:
        return 0.12;
    }
  }

  /// Intensidade do brilho.
  double _glowBlur() {
    switch (widget.state) {
      case AssistantState.idle:
        return 20;
      case AssistantState.listening:
        return 34;
      case AssistantState.thinking:
        return 28;
      case AssistantState.speaking:
        return 38;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _mainColor();

    return AnimatedBuilder(
      animation: Listenable.merge([
        _pulseController,
        _rotationController,
        _glowController,
      ]),
      builder: (context, child) {
        final pulseScale = 1 + (_pulseController.value * _pulseStrength());
        final glowBlur = _glowBlur() + (_glowController.value * 10);

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              /// Brilho exterior suave.
              Container(
                width: widget.size * pulseScale,
                height: widget.size * pulseScale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.25),
                      blurRadius: glowBlur,
                      spreadRadius: 8,
                    ),
                  ],
                ),
              ),

              /// Anel externo rotativo.
              Transform.rotate(
                angle: _rotationController.value * 2 * pi,
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: OrbRingPainter(
                    color: color.withOpacity(0.85),
                    strokeWidth: 3,
                  ),
                ),
              ),

              /// Segundo anel, a rodar ao contrário.
              Transform.rotate(
                angle: -_rotationController.value * 2 * pi * 0.7,
                child: CustomPaint(
                  size: Size(widget.size * 0.82, widget.size * 0.82),
                  painter: OrbRingPainter(
                    color: color.withOpacity(0.45),
                    strokeWidth: 2,
                  ),
                ),
              ),

              /// Núcleo central.
              Container(
                width: widget.size * 0.42 * pulseScale,
                height: widget.size * 0.42 * pulseScale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.95),
                      color.withOpacity(0.95),
                      color.withOpacity(0.35),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.45),
                      blurRadius: 24,
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),

              /// Texto no centro.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: widget.size * 0.5,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _label(),
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Painter para desenhar anéis segmentados.
/// Dá aquele aspeto mais "Jarvis / sci-fi".
class OrbRingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  OrbRingPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    /// Desenha pequenos arcos separados.
    final segments = [
      [0.1, 0.65],
      [1.05, 0.45],
      [1.9, 0.70],
      [3.0, 0.35],
      [3.7, 0.75],
      [4.85, 0.40],
      [5.5, 0.55],
    ];

    for (final segment in segments) {
      canvas.drawArc(rect, segment[0], segment[1], false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant OrbRingPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
