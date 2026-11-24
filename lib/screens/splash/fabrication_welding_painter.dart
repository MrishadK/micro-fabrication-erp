import 'dart:math';
import 'package:flutter/material.dart';

/// Bespoke CustomPainter rendering a blue-tinted industrial workshop silhouette,
/// structural steel framing, and animated welding spark glow effects.
class FabricationWeldingPainter extends CustomPainter {
  final double animationValue;

  FabricationWeldingPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Background atmospheric glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.2, 0.4),
        radius: 0.8,
        colors: [
          const Color(0xFF1E3A8A).withValues(alpha: 0.35),
          const Color(0xFF0F172A).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), glowPaint);

    // 2. Structural Steel Framework (Girders & Trusses)
    final steelPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.18)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    // Top overhead crane girder
    path.moveTo(0, h * 0.15);
    path.lineTo(w, h * 0.15);

    // Vertical structural columns
    path.moveTo(w * 0.25, h * 0.15);
    path.lineTo(w * 0.25, h * 0.95);
    path.moveTo(w * 0.75, h * 0.15);
    path.lineTo(w * 0.75, h * 0.95);

    // Diagonal truss supports
    path.moveTo(0, h * 0.15);
    path.lineTo(w * 0.25, h * 0.45);
    path.lineTo(w * 0.5, h * 0.15);
    path.lineTo(w * 0.75, h * 0.45);
    path.lineTo(w, h * 0.15);

    canvas.drawPath(path, steelPaint);

    // 3. Workstation workbench & fabrication anvil silhouette
    final benchPaint = Paint()
      ..color = const Color(0xFF0F2042).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final benchPath = Path()
      ..moveTo(w * 0.15, h * 0.95)
      ..lineTo(w * 0.15, h * 0.65)
      ..lineTo(w * 0.85, h * 0.65)
      ..lineTo(w * 0.85, h * 0.95)
      ..close();
    canvas.drawPath(benchPath, benchPaint);

    // Machine base top outline
    final outlinePaint = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.3)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(w * 0.15, h * 0.65),
      Offset(w * 0.85, h * 0.65),
      outlinePaint,
    );

    // Welder / robotic welding arm silhouette
    final armPath = Path()
      ..moveTo(w * 0.32, h * 0.65)
      ..lineTo(w * 0.42, h * 0.48)
      ..lineTo(w * 0.48, h * 0.52)
      ..lineTo(w * 0.45, h * 0.65)
      ..close();
    canvas.drawPath(armPath, benchPaint);

    // 4. Welding Torch Focal Point & Arc Glow
    final torchX = w * 0.49;
    final torchY = h * 0.53;

    final pulse = 0.7 + 0.3 * sin(animationValue * 2 * pi * 3);
    final flicker = 0.5 + 0.5 * cos(animationValue * 2 * pi * 7);

    // Core arc flash
    final arcPaint = Paint()
      ..color = const Color(0xFFE0F2FE).withValues(alpha: 0.7 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(torchX, torchY), 10 * pulse, arcPaint);

    final innerArcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * flicker);
    canvas.drawCircle(Offset(torchX, torchY), 3.5, innerArcPaint);

    // 5. Flying Welding Sparks
    final sparkPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.fill;

    final rand = Random(42);
    for (int i = 0; i < 12; i++) {
      final angle = -pi * 0.15 - rand.nextDouble() * pi * 0.8;
      final speed = 15.0 + rand.nextDouble() * 35.0;
      final phase = (animationValue * 2 + i * 0.12) % 1.0;
      final dist = speed * phase;

      final sparkX = torchX + cos(angle) * dist;
      final sparkY = torchY + sin(angle) * dist + 15 * phase * phase; // gravity
      final sparkAlpha = (1.0 - phase) * (0.4 + 0.6 * rand.nextDouble());

      sparkPaint.color = i % 3 == 0
          ? const Color(0xFFFDE047).withValues(alpha: sparkAlpha)
          : const Color(0xFF38BDF8).withValues(alpha: sparkAlpha);

      canvas.drawCircle(Offset(sparkX, sparkY), 1.2 * (1.0 - phase), sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FabricationWeldingPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
