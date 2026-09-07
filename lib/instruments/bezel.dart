import 'package:flutter/material.dart';

import '../app_colors.dart';

/// Two-tone instrument bezel: dark outer, 1px light inner top edge.
BoxDecoration instrumentBezel({
  required bool sun,
  Color? fill,
  Color? flash,
  Color? glow,
  double radius = 16,
}) {
  final base = fill ?? AppColors.cardBg(sun);
  return BoxDecoration(
    color: base,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: flash ??
          (glow != null
              ? glow.withValues(alpha: 0.45)
              : AppColors.borderFor(sun)),
      width: flash != null ? 2 : (glow != null ? 1.5 : 1),
    ),
    boxShadow: [
      BoxShadow(
        color: sun ? const Color(0x1A000000) : const Color(0x66000000),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
      if (!sun)
        const BoxShadow(
          color: Color(0x33FFFFFF),
          blurRadius: 0,
          offset: Offset(0, -1),
          spreadRadius: -1,
        ),
      if (glow != null)
        BoxShadow(
          color: glow.withValues(alpha: sun ? 0.08 : 0.18),
          blurRadius: 28,
          spreadRadius: -4,
        ),
    ],
  );
}
