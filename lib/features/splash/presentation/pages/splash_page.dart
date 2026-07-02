import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../../shared/presentation/widgets/space_background.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _navigationTimer = Timer(
      const Duration(milliseconds: 2600),
      () => mounted ? context.go(AppRoutes.onboarding) : null,
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final topGap = (constraints.maxHeight * 0.16).clamp(32, 120);
              final middleGap = (constraints.maxHeight * 0.16).clamp(32, 120);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 56)
                        .clamp(0, double.infinity)
                        .toDouble(),
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: topGap.toDouble()),
                      reduceMotion
                          ? const SpaceBotMark(size: 132)
                          : AnimatedBuilder(
                              animation: _controller,
                              builder: (context, child) {
                                return Transform.translate(
                                  offset: Offset(0, -8 * _controller.value),
                                  child: child,
                                );
                              },
                              child: const SpaceBotMark(size: 132),
                            ),
                      const SizedBox(height: 28),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                          children: const [
                            TextSpan(text: 'SPACEPILOT '),
                            TextSpan(
                              text: 'AI',
                              style: TextStyle(color: Color(0xFF9B5CFF)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your AI Storage Assistant',
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.76),
                        ),
                      ),
                      SizedBox(height: middleGap.toDouble()),
                      Text(
                        'Initializing AI Engine...',
                        style: textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: const LinearProgressIndicator(
                          value: 0.78,
                          minHeight: 8,
                          backgroundColor: Color(0xFF1D2545),
                          valueColor: AlwaysStoppedAnimation(
                            Color(0xFF9B5CFF),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '78%',
                        style: textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
