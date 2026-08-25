import 'package:flutter/material.dart';
import 'package:rate_helper/fonts.dart';

import 'app_colors.dart';

/// Shared bundled-font [TextStyle]s. Prefer these (or `const TextStyle`)
/// over allocating a new style on every rebuild.
abstract final class T {
  // Common dmSans variants
  static const dmSans = TextStyle(fontFamily: AppFonts.dmSans);

  static const dmSansBold = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontWeight: FontWeight.w700,
  );
  static const dmSansBlack = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontWeight: FontWeight.w900,
  );

  static const dmSans12 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 12);
  static const dmSans13 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 13);
  static const dmSans14 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 14);
  static const dmSans15 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 15);
  static const dmSans16 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 16);
  static const dmSans18 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 18);
  static const dmSans20 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 20);
  static const dmSans24 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 24);
  static const dmSans32 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 32);

  static const rateEmerald = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 36,
    fontWeight: FontWeight.w900,
    color: AppColors.emerald,
    height: 1,
  );
  static const rateCrimson = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 36,
    fontWeight: FontWeight.w900,
    color: AppColors.crimson,
    height: 1,
  );
  static const rateAmber = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 36,
    fontWeight: FontWeight.w900,
    color: AppColors.amber,
    height: 1,
  );
  static const rateWhite = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: 36,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    height: 1,
  );

  /// Zero-allocation lookup for the three threshold colours plus white.
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
  static const emptyAction = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontWeight: FontWeight.w800,
    fontSize: 14,
  );

  // Common jetBrainsMono variants
  static const jetBrainsMono = TextStyle(fontFamily: AppFonts.jetBrainsMono);
  static const jetBrainsMono10 = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 10,
  );
  static const jetBrainsMono11 = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 11,
  );
  static const jetBrainsMono12 = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 12,
  );
  static const jetBrainsMono13 = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 13,
  );
  static const jetBrainsMono14 = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 14,
  );
  static const jetBrainsMono16 = TextStyle(
    fontFamily: AppFonts.jetBrainsMono,
    fontSize: 16,
  );
}

