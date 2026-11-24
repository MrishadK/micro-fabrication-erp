import 'dart:math';
import 'package:flutter/material.dart';

/// Animated blue cloud synchronization icon above the initialization checklist.
/// Combines a prominent cloud icon with smoothly rotating dual sync arrows.
class CloudSyncHeaderIcon extends StatefulWidget {
  final double size;
  final bool isSpinning;

  const CloudSyncHeaderIcon({
    super.key,
    this.size = 54,
    this.isSpinning = true,
  });

  @override
  State<CloudSyncHeaderIcon> createState() => _CloudSyncHeaderIconState();
}

class _CloudSyncHeaderIconState extends State<CloudSyncHeaderIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.isSpinning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CloudSyncHeaderIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isSpinning && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle blue circular halo
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFEFF6FF),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),

          // Rotating synchronization arrows ring
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: _controller.value * 2 * pi,
                child: CustomPainterWidget(
                  size: Size(widget.size * 0.92, widget.size * 0.92),
                  painter: _SyncRingPainter(),
                ),
              );
            },
          ),

          // Center solid Cloud Icon
          Icon(
            Icons.cloud_rounded,
            size: widget.size * 0.52,
            color: const Color(0xFF2563EB),
          ),
        ],
      ),
    );
  }
}

class CustomPainterWidget extends StatelessWidget {
  final Size size;
  final CustomPainter painter;

  const CustomPainterWidget({
    super.key,
    required this.size,
    required this.painter,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: size, painter: painter);
  }
}

class _SyncRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = w / 2 - 2;
    final center = Offset(w / 2, h / 2);

    final trackPaint = Paint()
      ..color = const Color(0xFF93C5FD).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;

    // First arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      pi * 0.65,
      false,
      arcPaint,
    );

    // Second arc opposite
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      pi * 0.65,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
