import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<Offset> _slideAnimation;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(curve);
    _scaleAnimation = Tween<double>(begin: 0.86, end: 1).animate(curve);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.16),
      end: Offset.zero,
    ).animate(curve);

    _controller.forward();
    _navigationTimer = Timer(
      const Duration(milliseconds: 2600),
      _openOnboarding,
    );
  }

  void _openOnboarding() {
    if (!mounted) {
      return;
    }

    context.go(AppRoutes.onboarding);
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary,
              const Color(0xFF16B8A6),
              const Color(0xFF101828),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              const _SplashPattern(),
              Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _AppMark(),
                            const SizedBox(height: 28),
                            Text(
                              'SpacePilot AI',
                              textAlign: TextAlign.center,
                              style: textTheme.displaySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Smart storage optimization for a faster phone.',
                              textAlign: TextAlign.center,
                              style: textTheme.titleMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 34),
                            const _ProgressPill(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 28,
                child: Text(
                  'Optimizing storage signals...',
                  textAlign: TextAlign.center,
                  style: textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF2F6BFF),
            size: 34,
          ),
          Positioned(
            right: 21,
            bottom: 22,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Color(0xFF18A77A),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      height: 6,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const LinearProgressIndicator(
        backgroundColor: Colors.transparent,
        color: Colors.white,
        minHeight: 6,
      ),
    );
  }
}

class _SplashPattern extends StatelessWidget {
  const _SplashPattern();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _SplashPatternPainter()),
      ),
    );
  }
}

class _SplashPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var i = 0; i < 7; i++) {
      final inset = 26.0 + (i * 34);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset * 0.55,
            size.width - (inset * 1.35),
            size.height - (inset * 1.2),
          ),
          const Radius.circular(32),
        ),
        paint,
      );
    }

    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    for (var x = 28.0; x < size.width; x += 56) {
      for (var y = 42.0; y < size.height; y += 72) {
        canvas.drawCircle(Offset(x, y), 1.6, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
