import 'package:flutter/material.dart';

class SpaceBackground extends StatelessWidget {
  const SpaceBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF040914), Color(0xFF101D3C), Color(0xFF14264D)]
              : [
                  colorScheme.surface,
                  colorScheme.primaryContainer.withValues(alpha: 0.28),
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.88),
                ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: _SpaceBackdrop(colorScheme: colorScheme, isDark: isDark),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _SpaceBackdrop extends StatelessWidget {
  const _SpaceBackdrop({required this.colorScheme, required this.isDark});

  final ColorScheme colorScheme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      isComplex: true,
      willChange: false,
      painter: _SpaceBackdropPainter(colorScheme: colorScheme, isDark: isDark),
    );
  }
}

class _SpaceBackdropPainter extends CustomPainter {
  const _SpaceBackdropPainter({
    required this.colorScheme,
    required this.isDark,
  });

  final ColorScheme colorScheme;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final starPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.12);
    for (var i = 0; i < 70; i++) {
      final x = (i * 53) % size.width;
      final y = (i * 31) % size.height;
      canvas.drawCircle(Offset(x, y), i % 7 == 0 ? 1.4 : 0.8, starPaint);
    }

    final ringPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: isDark ? 0.10 : 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16;

    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.24),
      size.width * 0.20,
      ringPaint,
    );

    final orbitPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.72, size.height * 0.20),
        radius: size.width * 0.24,
      ),
      2.2,
      2.0,
      false,
      orbitPaint,
    );

    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              colorScheme.primary.withValues(alpha: 0.18),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.25, size.height * 0.18),
              radius: size.width * 0.26,
            ),
          );

    canvas.drawCircle(
      Offset(size.width * 0.25, size.height * 0.18),
      size.width * 0.26,
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant _SpaceBackdropPainter oldDelegate) {
    return false;
  }
}

class SpacePageList extends StatelessWidget {
  const SpacePageList({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 28),
    this.maxWidth = 1040,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extraWidth = (constraints.maxWidth - maxWidth)
            .clamp(0, double.infinity)
            .toDouble();
        final sideInset = extraWidth / 2;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            padding.left + sideInset,
            padding.top,
            padding.right + sideInset,
            padding.bottom,
          ),
          children: children,
        );
      },
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
    final isDark = colorScheme.brightness == Brightness.dark;

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
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: isDark ? 0.34 : 0.12),
            blurRadius: isDark ? 24 : 18,
            offset: const Offset(0, 10),
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
        center: Offset(
          center.dx - size.width * 0.35,
          center.dy + size.height * 0.18,
        ),
        width: size.width * 0.17,
        height: size.height * 0.32,
      ),
      bodyPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          center.dx + size.width * 0.35,
          center.dy + size.height * 0.18,
        ),
        width: size.width * 0.17,
        height: size.height * 0.32,
      ),
      bodyPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
