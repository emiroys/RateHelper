import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'fonts.dart';
import 'l10n.dart';
import 'models/weekly_archive_entry.dart';

/// One week in the HAFTALIK tab. Tap to expand the trip breakdown.
class WeeklyArchiveCard extends StatefulWidget {
  const WeeklyArchiveCard({
    super.key,
    required this.entry,
    required this.floors,
    this.fallbackTier,
    this.fallbackAcceptRate,
  });

  final WeeklyArchiveEntry entry;
  final List<WeeklyGoalFloor> floors;
  final String? fallbackTier;
  final double? fallbackAcceptRate;

  @override
  State<WeeklyArchiveCard> createState() => _WeeklyArchiveCardState();
}

class _WeeklyArchiveCardState extends State<WeeklyArchiveCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final goal = assessWeeklyGoal(
      entry,
      floors: widget.floors,
      fallbackTier: widget.fallbackTier,
      fallbackAcceptRate: widget.fallbackAcceptRate,
    );
    final acceptColor = goal.acceptMet ? AppColors.emerald : AppColors.crimson;
    final cancelColor = goal.cancelMet ? AppColors.emerald : AppColors.crimson;

    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.getFormattedDateRange(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.mutedText,
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Wrap, not Row: the Polish chip labels are too long to sit
                // side by side on a narrow sheet.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatChip(
                      label:
                          '${S.formatPercent(formatWeeklyRate(entry.acceptRate))} ${S.archiveAccept}',
                      color: acceptColor,
                    ),
                    _StatChip(
                      label:
                          '${S.formatPercent(formatWeeklyRate(entry.cancelRate))} ${S.archiveCancel}',
                      color: cancelColor,
                    ),
                  ],
                ),
                if (!entry.isLegacy) ...[
                  const SizedBox(height: 10),
                  Text(
                    S.archiveWeekSummary(
                      entry.completedTrips,
                      entry.acceptedCount,
                      entry.rejectedCount,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.jetBrainsMono,
                      fontSize: 12,
                      color: AppColors.mutedText,
                    ),
                  ),
                ],
                if (_expanded) ...[
                  const SizedBox(height: 12),
                  Container(height: 1, color: AppColors.hairline),
                  if (!entry.isLegacy) ...[
                    _detailRow(
                      S.archiveCompletedTrips,
                      '${entry.completedTrips}',
                    ),
                    _detailRow(
                      S.archiveCancelledTrips,
                      '${entry.resolvedCanceledTrips}',
                    ),
                    _detailRow(
                      S.archiveAcceptedRequests,
                      '${entry.acceptedCount}',
                    ),
                    _detailRow(
                      S.archiveRejectedRequests,
                      '${entry.rejectedCount}',
                    ),
                    _detailRow(
                      S.archiveTotalRequests,
                      '${entry.totalRequests}',
                    ),
                  ],
                  _detailRow(
                    S.archiveWeeklyGoal,
                    S.archiveGoalLine(
                      _thresholdLabel(goal.targetAcceptRate),
                      goal.goalMet,
                    ),
                    valueColor: goal.goalMet
                        ? AppColors.emerald
                        : AppColors.crimson,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _thresholdLabel(double? target) {
    if (target == null) return null;
    final text = target == target.roundToDouble()
        ? target.toStringAsFixed(0)
        : target.toStringAsFixed(1);
    return S.formatPercent(text);
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: AppFonts.jetBrainsMono,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor ?? Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppFonts.dmSans,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
