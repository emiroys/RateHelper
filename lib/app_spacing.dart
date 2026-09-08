import 'package:flutter/material.dart';

/// Single source of truth for all corner radii across the app.
///
/// Every card, button, tag, and modal must use one of these four values.
abstract final class AppRadius {
  /// Micro radius for progress tracks and subtle accents (4px).
  static const double xs = 4.0;

  /// Small tags, chips, badges, and minor accents (8px).
  static const double sm = 8.0;

  /// Standard cards, modal dialogs, list item rows, and inputs (16px).
  static const double md = 16.0;

  /// Hero cards, large containers, and bottom sheet tops (20px).
  static const double lg = 20.0;

  /// Circular action buttons, capsule badges, and overlay pills (999px).
  static const double pill = 999.0;

  static const BorderRadius xsBorder = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smBorder = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdBorder = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgBorder = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillBorder = BorderRadius.all(Radius.circular(pill));
}

/// Single source of truth for all padding, margins, and gaps across the app.
///
/// All spacing in the UI layer snaps to this disciplined 4-8-16-24-32 scale.
abstract final class AppSpacing {
  /// Micro gap (4px) — between icon and tight text, or badge padding.
  static const double xs = 4.0;

  /// Small gap (8px) — between icon and label, or tight vertical spacing.
  static const double sm = 8.0;

  /// Standard spacing (16px) — card insets, standard row gaps, screen edges.
  static const double md = 16.0;

  /// Large spacing (24px) — section gaps, prominent card margins.
  static const double lg = 24.0;

  /// Extra large spacing (32px) — major screen section dividers.
  static const double xl = 32.0;

  /// Standard card interior padding (16px all sides).
  static const EdgeInsets cardPadding = EdgeInsets.all(md);

  /// Standard screen edge horizontal padding (16px horizontal).
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: md);
}
