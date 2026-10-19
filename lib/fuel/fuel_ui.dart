import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_spacing.dart';
import '../fonts.dart';

const fuelEyebrowStyle = TextStyle(
  fontFamily: AppFonts.dmSans,
  fontSize: 12,
  fontWeight: FontWeight.w800,
  letterSpacing: 1.6,
  color: AppColors.labelText,
);

/// Eyebrow look for mixed-case strings (no `toUpperCase`: it breaks Turkish
/// dotted İ).
const fuelLabelStyle = TextStyle(
  fontFamily: AppFonts.dmSans,
  fontSize: 13,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.3,
  color: AppColors.labelText,
);

const fuelTitleStyle = TextStyle(
  fontFamily: AppFonts.dmSans,
  fontSize: 16,
  fontWeight: FontWeight.w800,
  color: Colors.white,
  height: 1.25,
);

const fuelMutedStyle = TextStyle(
  fontFamily: AppFonts.dmSans,
  fontSize: 12.5,
  fontWeight: FontWeight.w500,
  color: AppColors.mutedText,
  height: 1.35,
);

/// Rounded surface used by every block on the fuel screen.
class FuelCard extends StatelessWidget {
  const FuelCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Tints the border and adds a soft glow, for the highlighted card.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final glow = accent;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgBorder,
        border: Border.all(
          color: glow == null
              ? AppColors.hairline
              : glow.withValues(alpha: 0.5),
          width: glow == null ? 1 : 1.5,
        ),
        gradient: glow == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [glow.withValues(alpha: 0.14), AppColors.surface],
              ),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Large selectable pill: quick amounts, fuel type toggles.
class FuelPillButton extends StatelessWidget {
  const FuelPillButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppColors.actionAccent,
    this.height = 48,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? color.withValues(alpha: 0.18)
          : AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
        side: BorderSide(
          color: selected ? color.withValues(alpha: 0.6) : Colors.transparent,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdBorder,
        child: SizedBox(
          height: height,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: selected ? color : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showFuelSnack(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(fontFamily: AppFonts.dmSans),
      ),
      backgroundColor: AppColors.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
      action: action,
    ),
  );
}
