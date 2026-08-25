import 'package:flutter/material.dart';

/// Single source of truth for the app palette.
///
/// Every screen aliases these instead of re-declaring hex values, so the
/// red/amber/green threshold signalling (acceptance rate, cancellation budget,
/// hourly rate, earnings breakdown) is pixel-identical wherever it appears.
abstract final class AppColors {
  // Semantic threshold triad.
  static const emerald = Color(0xFF10B981);
  static const crimson = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);

  // Accents.
  static const gold = Color(0xFFFFD54A);
  static const designerGold = Color(0xFFD4AF37);

  // Surfaces.
  static const card = Color(0xFF1A1A1A);
  static const sheet = Color(0xFF121212);
  static const dialog = Color(0xFF161616);
  static const elevated = Color(0xFF1E1E1E);
  static const selected = Color(0xFF242424);
  static const inset = Color(0xFF0F0F0F);
  static const track = Color(0xFF2A2A2A);
  static const dialogAlt = Color(0xFF1E2430);
  static const radarHeader = Color(0xFF1A2E26);
  static const overlayPill = Color(0xE6161616);

  // Hairlines / borders.
  static const cardBorderColor = Color(0x0DFFFFFF);
  static const hairline = Color(0x1AFFFFFF);
  static const strongBorder = Color(0x33FFFFFF);

  /// Secondary/label text on dark cards. Chosen over `Colors.white38` so
  /// section headers stay legible in direct sunlight through a windscreen.
  static const labelText = Color(0xB3FFFFFF); // 70%

  /// Tertiary text (hints, timestamps, empty-state bodies).
  static const mutedText = Color(0x99FFFFFF); // 60%

  /// Disabled control text — still readable, unlike `Colors.white24`.
  static const disabledText = Color(0x66FFFFFF); // 40%
}
