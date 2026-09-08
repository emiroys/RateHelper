import 'package:flutter/material.dart';
import 'package:rate_helper/fonts.dart';

import 'app_colors.dart';

/// Single source of truth for all typography across the app.
///
/// Consolidates ad-hoc font sizes into 6 disciplined functional roles:
/// - [heroNumber] (48px) — All prominent hero metrics with tabular figures.
/// - [sectionTitle] (20px) — Major section titles and modal headers.
/// - [headline] (16px) — Card headers, item titles, event names.
/// - [body] (14px) — Primary content, form inputs, list item subtitles.
/// - [caption] (12px) — Timestamps, badges, secondary hints.
/// - [eyebrow] (11px) — All-caps letterspaced category badges ("KABUL ORANI").
abstract final class AppTextStyles {
  // Functional Size Scale
  static const double heroNumber = 48.0;
  static const double sectionTitle = 20.0;
  static const double headline = 16.0;
  static const double body = 14.0;
  static const double caption = 12.0;
  static const double eyebrow = 11.0;

  // Base DM Sans Styles
  static const TextStyle hero = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: heroNumber,
    fontWeight: FontWeight.w900,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1.0,
  );

  /// Dynamic hero metric for acceptance rate or earnings with color signalling.
  static TextStyle heroRate(Color color) => hero.copyWith(color: color);

  static const TextStyle sectionTitleStyle = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: sectionTitle,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.2,
  );

  static const TextStyle headlineStyle = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: headline,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: body,
    fontWeight: FontWeight.w500,
    color: Colors.white,
    height: 1.4,
  );

  static const TextStyle captionStyle = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: caption,
    fontWeight: FontWeight.w500,
    color: AppColors.mutedText,
  );

  /// Eyebrow category tag (e.g. "KABUL ORANI", "HESAP KESİM").
  /// Preserves the exact uppercase + wide tracking aesthetic.
  static TextStyle eyebrowStyle([Color color = AppColors.labelText]) =>
      TextStyle(
        fontFamily: AppFonts.dmSans,
        fontSize: eyebrow,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: color,
      );

  // Tabular numeric font for dynamically updating counters (no jitter)
  static TextStyle tabularNumbers({
    double fontSize = body,
    FontWeight fontWeight = FontWeight.w700,
    Color color = Colors.white,
  }) =>
      TextStyle(
        fontFamily: AppFonts.dmSans,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      );

  /// STRICT tabular monospace: ONLY for aligned PLN breakdown tables and KK4181R signature.
  static TextStyle tabularMonospace({
    double fontSize = body,
    FontWeight fontWeight = FontWeight.w700,
    Color color = Colors.white,
  }) =>
      TextStyle(
        fontFamily: AppFonts.jetBrainsMono,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      );
}

/// Backwards-compatibility alias wrapper for legacy references.
abstract final class T {
  static const dmSans = TextStyle(fontFamily: AppFonts.dmSans);

  static const dmSansBold = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontWeight: FontWeight.w700,
  );
  static const dmSansBlack = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontWeight: FontWeight.w900,
  );

  static const dmSans12 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: AppTextStyles.caption);
  static const dmSans13 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 13);
  static const dmSans14 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: AppTextStyles.body);
  static const dmSans15 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 15);
  static const dmSans16 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: AppTextStyles.headline);
  static const dmSans18 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 18);
  static const dmSans20 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: AppTextStyles.sectionTitle);
  static const dmSans24 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 24);
  static const dmSans32 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 32);

  static const rateEmerald = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: AppTextStyles.heroNumber,
    fontWeight: FontWeight.w900,
    color: AppColors.emerald,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );
  static const rateCrimson = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: AppTextStyles.heroNumber,
    fontWeight: FontWeight.w900,
    color: AppColors.crimson,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );
  static const rateAmber = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: AppTextStyles.heroNumber,
    fontWeight: FontWeight.w900,
    color: AppColors.amber,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );
  static const rateWhite = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: AppTextStyles.heroNumber,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );

  static TextStyle rateFor(Color color) {
    if (color == AppColors.crimson) return rateCrimson;
    if (color == AppColors.amber) return rateAmber;
    if (color == Colors.white) return rateWhite;
    return rateEmerald;
  }

  static const emptyTitle = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  static const emptyTitleCompact = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );
  static const emptyBody = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: AppTextStyles.body,
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
  static const emptyAction = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontWeight: FontWeight.w800,
    fontSize: AppTextStyles.body,
  );

  static const jetBrainsMono = TextStyle(fontFamily: AppFonts.jetBrainsMono);
  static const jetBrainsMono10 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 10);
  static const jetBrainsMono11 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 11);
  static const jetBrainsMono12 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 12);
  static const jetBrainsMono13 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 13);
  static const jetBrainsMono14 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 14);
  static const jetBrainsMono16 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 16);
}

