import 'package:flutter/material.dart';
import 'package:rate_helper/fonts.dart';

/// Centralized text styles to avoid inline GoogleFonts allocations on every rebuild.
/// Reusing these static final objects reduces GC pressure and unlocks `const` for Text widgets.
abstract final class T {
  // Common dmSans variants
  static final dmSans = TextStyle(fontFamily: AppFonts.dmSans);
  
  static final dmSansBold = TextStyle(fontFamily: AppFonts.dmSans, fontWeight: FontWeight.w700);
  static final dmSansBlack = TextStyle(fontFamily: AppFonts.dmSans, fontWeight: FontWeight.w900);
  
  static final dmSans12 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 12);
  static final dmSans13 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 13);
  static final dmSans14 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 14);
  static final dmSans15 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 15);
  static final dmSans16 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 16);
  static final dmSans18 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 18);
  static final dmSans20 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 20);
  static final dmSans24 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 24);
  static final dmSans32 = TextStyle(fontFamily: AppFonts.dmSans, fontSize: 32);

  // Common jetBrainsMono variants
  static final jetBrainsMono = TextStyle(fontFamily: AppFonts.jetBrainsMono);
  static final jetBrainsMono10 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 10);
  static final jetBrainsMono11 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 11);
  static final jetBrainsMono12 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 12);
  static final jetBrainsMono13 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 13);
  static final jetBrainsMono14 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 14);
  static final jetBrainsMono16 = TextStyle(fontFamily: AppFonts.jetBrainsMono, fontSize: 16);
}
