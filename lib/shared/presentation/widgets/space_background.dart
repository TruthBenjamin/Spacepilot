import 'package:flutter/material.dart';

class SpaceBackground extends StatelessWidget {
  const SpaceBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF050716),
            Color(0xFF0A0E24),
            Color(0xFF120B2F),
          ],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _StarField()),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class SpaceCard extends StatelessWidget {
  const SpaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.gradient,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient:
            gradient ??
            LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surface.withValues(alpha: 0.94),
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.74),
              ],
            ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SpaceBotMark extends StatelessWidget {
  const SpaceBotMark({this.size = 118, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SpaceBotPainter()),
    );
  }
}

class _StarField extends StatelessWidget {
  const _StarField();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _StarFieldPainter());
  }
}

class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.22);
    for (var i = 0; i < 90; i++) {
      final x = ((i * 47) % size.width).toDouble();
      final y = ((i * 89) % size.height).toDouble();
      final radius = i % 9 == 0 ? 1.4 : 0.7;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF7C3AED).withValues(alpha: 0.32),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.82, size.height * 0.18),
        radius: size.width * 0.46,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.18),
      size.width * 0.46,
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SpaceBotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00E5FF).withValues(alpha: 0.32),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.width / 2));
    canvas.drawCircle(center, size.width * 0.48, glowPaint);

    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEFF6FF), Color(0xFF6578B6)],
      ).createShader(Offset.zero & size);
    final darkPaint = Paint()..color = const Color(0xFF101832);
    final cyanPaint = Paint()..color = const Color(0xFF00E5FF);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + size.height * 0.16),
        width: size.width * 0.48,
        height: size.height * 0.44,
      ),
      bodyPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy - size.height * 0.08),
          width: size.width * 0.58,
          height: size.height * 0.42,
        ),
        Radius.circular(size.width * 0.18),
      ),
      bodyPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy - size.height * 0.06),
          width: size.width * 0.42,
          height: size.height * 0.22,
        ),
        Radius.circular(size.width * 0.1),
      ),
      darkPaint,
    );
    canvas.drawCircle(
      Offset(center.dx - size.width * 0.11, center.dy - size.height * 0.06),
      size.width * 0.025,
      cyanPaint,
    );
    canvas.drawCircle(
      Offset(center.dx + size.width * 0.11, center.dy - size.height * 0.06),
      size.width * 0.025,
      cyanPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - size.width * 0.35, center.dy + size.height * 0.18),
        width: size.width * 0.17,
        height: size.height * 0.32,
      ),
      bodyPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + size.width * 0.35, center.dy + size.height * 0.18),
        width: size.width * 0.17,
        height: size.height * 0.32,
      ),
      bodyPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
