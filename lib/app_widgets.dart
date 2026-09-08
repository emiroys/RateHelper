import 'package:flutter/material.dart';
import 'package:rate_helper/fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// Minimum tap area for anything the driver may hit while the car is moving.
const double kMinTouchTarget = 48.0;

/// Wraps a small visual (usually an icon) in a forgiving [kMinTouchTarget]
/// square hit area without changing how large the icon itself looks.
class AppTapTarget extends StatelessWidget {
  const AppTapTarget({
    super.key,
    required this.onTap,
    required this.child,
    this.tooltip,
    this.size = kMinTouchTarget,
  });

  final VoidCallback? onTap;
  final Widget child;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(child: child),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Shared "nothing here yet" panel: icon medallion, title, explanation and an
/// optional action, so no list ever renders as a bare blank area.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.accent = AppColors.emerald,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color accent;

  /// Tighter spacing for use inside a card rather than a full page.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: compact ? 20 : 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? 14 : 20),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Icon(
                icon,
                color: accent,
                size: compact ? 26 : 40,
              ),
            ),
            SizedBox(height: compact ? 12 : 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: compact ? T.emptyTitleCompact : T.emptyTitle,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: compact ? T.emptyBodyCompact : T.emptyBody,
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? 14 : 22),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.18),
                    foregroundColor: accent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: accent.withValues(alpha: 0.5)),
                    ),
                  ),
                  onPressed: onAction,
                  child: Text(
                    actionLabel!,
                    textAlign: TextAlign.center,
                    style: T.emptyAction,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Primary filled CTA button with responsive InkWell ripple.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color = AppColors.emerald,
    this.textColor = Colors.white,
    this.enabled = true,
    this.height = 54.0,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : AppColors.surfaceElevated;
    final effectiveTextColor = enabled ? textColor : AppColors.disabledText;

    return Material(
      color: effectiveColor,
      borderRadius: AppRadius.mdBorder,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: AppRadius.mdBorder,
        splashColor: Colors.white.withValues(alpha: 0.18),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: effectiveTextColor, size: 20),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: AppTextStyles.body,
                    fontWeight: FontWeight.w800,
                    color: effectiveTextColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outlined secondary button with tactile InkWell ripple.
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.accentColor = Colors.white,
    this.height = 48.0,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color accentColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
        side: BorderSide(color: AppColors.hairline, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdBorder,
        splashColor: accentColor.withValues(alpha: 0.12),
        highlightColor: accentColor.withValues(alpha: 0.06),
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: accentColor, size: 18),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: AppTextStyles.body,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular/pill action button with colored tint and rich InkWell ripple.
/// Matches the tactile feel of the overlay pill buttons.
class AppIconActionButton extends StatelessWidget {
  const AppIconActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tintColor,
    this.size = 60.0,
    this.iconSize = 28.0,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? tintColor;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = tintColor ?? Colors.white;
    final button = Material(
      color: color.withValues(alpha: 0.14),
      shape: CircleBorder(
        side: BorderSide(color: color.withValues(alpha: 0.40), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        splashColor: color.withValues(alpha: 0.35),
        highlightColor: color.withValues(alpha: 0.15),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(icon, color: color, size: iconSize),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Destructive danger button with red outline and subtle red fill.
class AppDangerButton extends StatelessWidget {
  const AppDangerButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.crimson.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
        side: BorderSide(
          color: AppColors.crimson.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdBorder,
        splashColor: AppColors.crimson.withValues(alpha: 0.25),
        highlightColor: AppColors.crimson.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: AppColors.crimson, size: 18),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: AppColors.crimson,
                  fontSize: AppTextStyles.body,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

