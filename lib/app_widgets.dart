import 'package:flutter/material.dart';

import 'app_colors.dart';
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
