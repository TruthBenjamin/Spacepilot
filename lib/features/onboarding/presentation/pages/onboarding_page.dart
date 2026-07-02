import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/onboarding_preferences_service.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/presentation/widgets/space_background.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  final OnboardingPreferencesService _preferences =
      OnboardingPreferencesService();
  int _index = 0;
  bool _isFinishing = false;

  static const _slides = [
    _Slide(
      title: 'AI that keeps your phone clean & fast',
      body:
          'Find, review and remove junk files, duplicates, and large files easily.',
      icon: Icons.cleaning_services_rounded,
    ),
    _Slide(
      title: 'Private local intelligence',
      body: 'SpacePilot analyzes your storage on-device. No cloud AI required.',
      icon: Icons.verified_user_rounded,
    ),
    _Slide(
      title: 'Agentic cleanup insights',
      body:
          'Monitor storage growth, predict shortages, and get safe cleanup suggestions.',
      icon: Icons.smart_toy_rounded,
    ),
    _Slide(
      title: 'You stay in control',
      body: 'Every cleanup action is reviewed before anything is deleted.',
      icon: Icons.rule_rounded,
    ),
  ];

  bool get _isLast => _index == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    await _preferences.setOnboardingCompleted();
    if (!mounted) return;

    context.go(AppRoutes.dashboard);
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      'Smart Cleaning',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFFB9C4F6),
                      ),
                    ),
                    const Spacer(),
                    TextButton(onPressed: _finish, child: const Text('Skip')),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, index) {
                      return _OnboardingSlide(slide: _slides[index]);
                    },
                  ),
                ),
                Row(
                  children: [
                    _Dots(count: _slides.length, active: _index),
                    const Spacer(),
                    FilledButton(
                      onPressed: _isFinishing ? null : _next,
                      child: Text(_isLast ? 'Start' : 'Next'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 560;
        final artSize = math.min(
          260.0,
          math.min(constraints.maxWidth * 0.78, constraints.maxHeight * 0.42),
        );

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: compactHeight ? 24 : 48),
                RichText(
                  text: TextSpan(
                    style: textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                    children: [
                      TextSpan(text: '${slide.title.split('&').first.trim()} '),
                      if (slide.title.contains('&'))
                        const TextSpan(
                          text: '& fast',
                          style: TextStyle(color: Color(0xFF9B5CFF)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  slide.body,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.74),
                    height: 1.45,
                  ),
                ),
                SizedBox(height: compactHeight ? 28 : 48),
                Center(
                  child: SizedBox.square(
                    dimension: artSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: artSize * 0.88,
                          height: artSize * 0.88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(
                                0xFF9B5CFF,
                              ).withValues(alpha: 0.36),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF7C3AED,
                                ).withValues(alpha: 0.28),
                                blurRadius: 34,
                              ),
                            ],
                          ),
                        ),
                        Transform.rotate(
                          angle: -0.28,
                          child: SpaceCard(
                            padding: EdgeInsets.all(artSize * 0.1),
                            child: Icon(
                              slide.icon,
                              color: const Color(0xFFB990FF),
                              size: artSize * 0.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: compactHeight ? 24 : 48),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: i == active ? 18 : 7,
            height: 7,
            margin: const EdgeInsets.only(right: 7),
            decoration: BoxDecoration(
              color: i == active ? const Color(0xFF9B5CFF) : Colors.white24,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

class _Slide {
  const _Slide({required this.title, required this.body, required this.icon});

  final String title;
  final String body;
  final IconData icon;
}
