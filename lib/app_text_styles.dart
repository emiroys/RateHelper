import 'package:flutter/material.dart';
import 'package:rate_helper/fonts.dart';

import 'app_colors.dart';

/// Shared bundled-font [TextStyle]s — semantic tokens only.
/// Prefer these over allocating a new style on every rebuild.
abstract final class T {
  static const _tabular = [FontFeature.tabularFigures()];

  // ── Heroes (tabular figures — counters / financial metrics) ────────────
  static const heroXLarge = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 56,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    height: 1,
    fontFeatures: _tabular,
  );
  static const heroLarge = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 48,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    height: 1,
    fontFeatures: _tabular,
  );
  static const heroMedium = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 46,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    height: 1,
    fontFeatures: _tabular,
  );
  static const heroSmall = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 36,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    height: 1,
    fontFeatures: _tabular,
  );

  /// Compact overlay AR numeral (~30px) so the secondary ratio line fits
  /// inside the 80dp pill FittedBox.
  static const heroOverlay = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1,
    fontFeatures: _tabular,
  );

  // ── Labels / chrome ────────────────────────────────────────────────────
  /// Sheet / card eyebrow: 10px, w700, letterSpacing 2, labelText.
  static const eyebrow = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 2,
    color: AppColors.labelText,
  );

  /// Unified section header: 12px, w800, letterSpacing 2.
  static const sectionHeader = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 2,
    color: AppColors.labelText,
  );

  static const titleLg = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  static const titleMd = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 0.3,
  );
  static const titleSm = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  static const titleXs = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );

  static const body = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Colors.white,
  );
  static const bodyStrong = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  static const label = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.mutedText,
  );
  static const labelStrong = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );
  static const caption = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.mutedText,
  );
  static const captionSm = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.mutedText,
  );
  static const micro = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.mutedText,
  );
  static const nano = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 9,
    fontWeight: FontWeight.w600,
    color: AppColors.mutedText,
  );

  // ── Rate / threshold numerals (heroSmall + mono + tabular) ─────────────
  static const rateEmerald = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.emerald,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateCrimson = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.crimson,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateAmber = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.amber,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateWhite = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateSunInk = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.sunInk,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateSunEmerald = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.sunEmerald,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateSunCrimson = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.sunCrimson,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateSunAmber = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.sunAmber,
    height: 1,
    fontFeatures: _tabular,
  );

  static const rateOverlayEmerald = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.emerald,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateOverlayCrimson = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.crimson,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateOverlayAmber = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.amber,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateOverlayWhite = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateOverlaySunInk = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.sunInk,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateOverlaySunEmerald = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.sunEmerald,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateOverlaySunCrimson = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.sunCrimson,
    height: 1,
    fontFeatures: _tabular,
  );
  static const rateOverlaySunAmber = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.sunAmber,
    height: 1,
    fontFeatures: _tabular,
  );

  /// Zero-allocation lookup for the three threshold colours plus white.
  static TextStyle rateFor(Color color, {bool sun = false}) {
    if (sun) {
      if (color == AppColors.crimson || color == AppColors.sunCrimson) {
        return rateSunCrimson;
      }
      if (color == AppColors.amber || color == AppColors.sunAmber) {
        return rateSunAmber;
      }
      if (color == Colors.white || color == AppColors.sunInk) {
        return rateSunInk;
      }
      return rateSunEmerald;
    }
    if (color == AppColors.crimson) return rateCrimson;
    if (color == AppColors.amber) return rateAmber;
    if (color == Colors.white) return rateWhite;
    return rateEmerald;
  }

  static TextStyle rateOverlayFor(Color color, {bool sun = false}) {
    if (sun) {
      if (color == AppColors.crimson || color == AppColors.sunCrimson) {
        return rateOverlaySunCrimson;
      }
      if (color == AppColors.amber || color == AppColors.sunAmber) {
        return rateOverlaySunAmber;
      }
      if (color == Colors.white || color == AppColors.sunInk) {
        return rateOverlaySunInk;
      }
      return rateOverlaySunEmerald;
    }
    if (color == AppColors.crimson) return rateOverlayCrimson;
    if (color == AppColors.amber) return rateOverlayAmber;
    if (color == Colors.white) return rateOverlayWhite;
    return rateOverlayEmerald;
  }

  // ── Empty states ───────────────────────────────────────────────────────
  static const emptyTitle = titleLg;
  static const emptyTitleCompact = titleXs;
  static const emptyBody = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.mutedText,
  );
  static const emptyBodyCompact = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.mutedText,
  );
  static const emptyAction = bodyStrong;

  // ── Overlay secondary line ─────────────────────────────────────────────
  static const overlayRatio = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.labelText,
    height: 1.1,
    fontFeatures: _tabular,
  );
  static const overlayRatioSun = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.sunLabel,
    height: 1.1,
    fontFeatures: _tabular,
  );

  static TextStyle overlayRatioFor({bool sun = false}) =>
      sun ? overlayRatioSun : overlayRatio;

  // ── Mono (logs / crash dump) ───────────────────────────────────────────
  static const mono = TextStyle(fontFamily: AppFonts.jetBrainsMono);
  static const monoSm = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 11,
    color: Colors.white,
    height: 1.4,
  );
  static const monoMd = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 13,
    color: Colors.white,
  );
}
