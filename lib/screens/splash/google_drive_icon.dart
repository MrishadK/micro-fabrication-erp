import 'package:flutter/material.dart';

/// Clean, pixel-perfect Google Drive Logo vector widget for checklist rows.
class GoogleDriveIcon extends StatelessWidget {
  final double size;
  const GoogleDriveIcon({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleDrivePainter(),
      ),
    );
  }
}

class _GoogleDrivePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Google Drive 3-color rounded triangle
    // 1. Yellow banner (top right)
    final yellowPaint = Paint()
      ..color = const Color(0xFFFFBA00)
      ..style = PaintingStyle.fill;
    final yellowPath = Path()
      ..moveTo(w * 0.35, h * 0.08)
      ..lineTo(w * 0.65, h * 0.08)
      ..lineTo(w * 0.96, h * 0.62)
      ..lineTo(w * 0.66, h * 0.62)
      ..close();
    canvas.drawPath(yellowPath, yellowPaint);

    // 2. Green banner (right to bottom-left)
    final greenPaint = Paint()
      ..color = const Color(0xFF00AC47)
      ..style = PaintingStyle.fill;
    final greenPath = Path()
      ..moveTo(w * 0.65, h * 0.08)
      ..lineTo(w * 0.35, h * 0.08)
      ..lineTo(w * 0.04, h * 0.62)
      ..lineTo(w * 0.34, h * 0.62)
      ..close();
    canvas.drawPath(greenPath, greenPaint);

    // 3. Blue banner (bottom)
    final bluePaint = Paint()
      ..color = const Color(0xFF0066DA)
      ..style = PaintingStyle.fill;
    final bluePath = Path()
      ..moveTo(w * 0.19, h * 0.88)
      ..lineTo(w * 0.81, h * 0.88)
      ..lineTo(w * 0.96, h * 0.62)
      ..lineTo(w * 0.34, h * 0.62)
      ..close();
    canvas.drawPath(bluePath, bluePaint);

    // Red/Dark accent overlap
    final accentPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.fill;
    final accentPath = Path()
      ..moveTo(w * 0.19, h * 0.88)
      ..lineTo(w * 0.04, h * 0.62)
      ..lineTo(w * 0.34, h * 0.62)
      ..close();
    canvas.drawPath(accentPath, accentPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
