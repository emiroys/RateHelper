import 'package:flutter/material.dart';

/// Single source of truth for the app palette.
///
/// Dark surfaces are exactly three tokens: [base], [raised], [inset].
/// Hairlines are [hairlineFaint], [hairline], [hairlineStrong].
abstract final class AppColors {
  // Semantic threshold triad — do not change hex values.
  static const emerald = Color(0xFF10B981);
  static const crimson = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);

  /// Achievements / records only — not for FABs or generic accents.
  static const gold = Color(0xFFFFD54A);

  // ── Dark surfaces (exactly 3) ──────────────────────────────────────────
  /// Page / sheet / dialog canvas.
  static const base = Color(0xFF121212);

  /// Cards, elevated chrome, selected rows, tracks.
  static const raised = Color(0xFF1A1A1A);

  /// Recessed wells and input fills.
  static const inset = Color(0xFF0F0F0F);

  /// Canonical card fill — alias of [raised] (Phase 2 geometry contract).
  static const card = raised;

  // Legacy aliases — call sites still use pre-consolidation names.
  static const sheet = base;
  static const dialog = Color(0xFF161616);
  static const elevated = Color(0xFF1E1E1E);
  static const selected = Color(0xFF242424);
  static const track = Color(0xFF2A2A2A);
  static const dialogAlt = Color(0xFF1E2430);
  static const radarHeader = Color(0xFF1A2E26);
  static const designerGold = Color(0xFFD4AF37);

  // ── Hairlines (exactly 3) ──────────────────────────────────────────────
  /// ~5% white — default card border.
  static const hairlineFaint = Color(0x0DFFFFFF);

  /// ~10% white — secondary dividers / chrome.
  static const hairline = Color(0x1AFFFFFF);

  /// ~20% white — strong borders / focus rings.
  static const hairlineStrong = Color(0x33FFFFFF);

  static const cardBorderColor = hairlineFaint;
  static const strongBorder = hairlineStrong;

  /// Secondary/label text on dark cards.
  static const labelText = Color(0xB3FFFFFF); // 70%

  /// Tertiary text (hints, timestamps, empty-state bodies).
  static const mutedText = Color(0x99FFFFFF); // 60%

  /// Disabled control text — still readable, unlike `Colors.white24`.
  static const disabledText = Color(0x66FFFFFF); // 40%

  /// Overlay pill fill (isolate-only).
  static const overlayPill = Color(0xE6161616);

  // ── Sun-mode inverted field ────────────────────────────────────────────
  // Not pure white — limits bloom and panel power.
  static const sunField = Color(0xFFF2F2F2);
  static const sunCard = Color(0xFFE6E6E6);
  static const sunElevated = Color(0xFFDADADA);
  static const sunInk = Color(0xFF0A0A0A);
  static const sunTrack = Color(0xFFC8C8C8);
  static const sunOverlayPill = Color(0xF2F2F2F2);

  /// Brighter red-orange for sun mode — holds up better for deuteranomaly.
  static const sunCrimson = Color(0xFFFF5A4E);
  static const sunEmerald = Color(0xFF047857);
  static const sunAmber = Color(0xFFB45309);

  static const sunLabel = Color(0xE60A0A0A); // 90%
  static const sunMuted = Color(0xCC0A0A0A); // 80%

  static Color scaffold(bool sun) => sun ? sunField : base;
  static Color cardBg(bool sun) => sun ? sunCard : raised;
  static Color elevatedBg(bool sun) => sun ? sunElevated : raised;
  static Color ink(bool sun) => sun ? sunInk : Colors.white;
  static Color labelFor(bool sun) => sun ? sunLabel : labelText;
  static Color mutedFor(bool sun) => sun ? sunMuted : mutedText;
  static Color crimsonFor(bool sun) => sun ? sunCrimson : crimson;
  static Color emeraldFor(bool sun) => sun ? sunEmerald : emerald;
  static Color amberFor(bool sun) => sun ? sunAmber : amber;
  static Color goldFor(bool sun) => sun ? const Color(0xFFA16207) : gold;
  static Color borderFor(bool sun) =>
      sun ? const Color(0x33000000) : hairlineFaint;
  static Color hairlineFor(bool sun) =>
      sun ? const Color(0x4D000000) : hairline;
  static Color trackFor(bool sun) => sun ? sunTrack : raised;
  static Color overlayPillFor(bool sun) => sun ? sunOverlayPill : overlayPill;

  static Color stateFor(Color dark, bool sun) {
    if (dark == crimson) return crimsonFor(sun);
    if (dark == amber) return amberFor(sun);
    if (dark == emerald) return emeraldFor(sun);
    if (dark == gold) return goldFor(sun);
    return dark;
  }
}
