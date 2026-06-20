import 'package:flutter/material.dart';

@immutable
final class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.pill,
  });

  static const standard = AppRadii(sm: 8, md: 12, lg: 16, xl: 24, pill: 999);

  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double pill;

  BorderRadius get card => BorderRadius.all(Radius.circular(lg));
  BorderRadius get button => BorderRadius.all(Radius.circular(md));
  BorderRadius get sheet => BorderRadius.vertical(top: Radius.circular(xl));

  @override
  AppRadii copyWith({
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? pill,
  }) {
    return AppRadii(
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) {
      return this;
    }

    return AppRadii(
      sm: _lerp(sm, other.sm, t),
      md: _lerp(md, other.md, t),
      lg: _lerp(lg, other.lg, t),
      xl: _lerp(xl, other.xl, t),
      pill: _lerp(pill, other.pill, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
