import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_text_styles.dart';

class LoadSegment {
  const LoadSegment({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

/// Horizontal proportional bar. Take-home should be the last (rightmost) slice.
class LoadMeter extends StatelessWidget {
  const LoadMeter({
    super.key,
    required this.segments,
    this.height = 18,
    this.sun = false,
  });

  final List<LoadSegment> segments;
  final double height;
  final bool sun;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (s, e) => s + e.value.abs());
    final safe = total <= 0 ? 1.0 : total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final seg in segments)
              if (seg.value.abs() > 0.01)
                Expanded(
                  flex: (seg.value.abs() / safe * 1000).round().clamp(1, 1000),
                  child: ColoredBox(color: seg.color),
                ),
          ],
        ),
      ),
    );
  }
}

class LoadMeterLegend extends StatelessWidget {
  const LoadMeterLegend({
    super.key,
    required this.segments,
    this.sun = false,
  });

  final List<LoadSegment> segments;
  final bool sun;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final seg in segments)
          if (seg.value.abs() > 0.01)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: seg.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  seg.label,
                  style: T.caption.copyWith(color: AppColors.mutedFor(sun)),
                ),
              ],
            ),
      ],
    );
  }
}
