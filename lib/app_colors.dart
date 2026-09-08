import 'package:flutter/material.dart';

/// Single source of truth for the app palette.
///
/// Every screen aliases these instead of re-declaring hex values, so the
/// red/amber/green threshold signalling (acceptance rate, cancellation budget,
/// hourly rate, earnings breakdown) is pixel-identical wherever it appears.
abstract final class AppColors {
  // Semantic threshold triad (preserved as-is).
  static const emerald = Color(0xFF10B981);
  static const crimson = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);

  // Accents.
  /// Milestone/record achievement gold (🏆 context only).
  static const recordGold = Color(0xFFFFD54A);

  /// Utility/action accent (quick fuel-add, interactive tools) — distinct from record gold.
  static const actionAccent = Color(0xFF38BDF8);

  /// Backwards-compatible alias for recordGold.
  static const gold = recordGold;

  /// Signature gold for KK4181R badge.
  static const designerGold = Color(0xFFD4AF37);

  // Consolidated 3-Tone Dark Surface Architecture:
  /// Tone 1: Deep screen canvas background (darkest).
  static const background = Color(0xFF0D0D0D);

  /// Tone 2: Standard card, sheet, and dialog surface.
  static const surface = Color(0xFF161616);

  /// Tone 3: Nested cards, progress tracks, active/elevated components.
  static const surfaceElevated = Color(0xFF1E1E1E);

  // Backwards-compatible aliases mapped to the 3-tone system:
  static const card = surface;
  static const sheet = surface;
  static const dialog = surface;
  static const elevated = surfaceElevated;
  static const selected = surfaceElevated;
  static const inset = background;
  static const track = surfaceElevated;
  static const dialogAlt = surfaceElevated;
  static const radarHeader = surface;
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
