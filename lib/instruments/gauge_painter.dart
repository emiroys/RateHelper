import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_text_styles.dart';
import '../format_rate.dart';

/// 270° sweep arc with tick marks and a physical redline tick at [redline].
///
/// [value] is the numeral. [arcValue] is what the needle/fill paints — pass a
/// swept copy during the ignition self-test so the number never lies.
class ArcGauge extends StatelessWidget {
  const ArcGauge({
    super.key,
    required this.value,
    required this.arcValue,
    this.min = 0,
    this.max = 100,
    this.redline,
    required this.color,
    this.label,
    this.caption,
    this.sun = false,
    this.size = 220,
  });

  final double value;
  final double arcValue;
  final double min;
  final double max;
  final double? redline;
  final Color color;
  final String? label;
  final String? caption;
  final bool sun;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = AppColors.ink(sun);
    return SizedBox(
      width: size,
      height: size * 0.72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: GaugePainter(
                value: arcValue,
                min: min,
                max: max,
                redline: redline,
                color: color,
                sun: sun,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: size * 0.08),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null)
                  Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.bodyStrong.copyWith(color: AppColors.labelFor(sun), letterSpacing: 1.2),
                  ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatRatePercent(value),
                    style: T.rateFor(color, sun: sun).copyWith(fontSize: 42),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.body.copyWith(color: ink, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GaugePainter extends CustomPainter {
  GaugePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.redline,
    required this.color,
    required this.sun,
  });

  final double value;
  final double min;
  final double max;
  final double? redline;
  final Color color;
  final bool sun;

  static const _start = math.pi * 0.75; // 135°
  static const _sweep = math.pi * 1.5; // 270°

  double _t(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.58);
    final radius = math.min(size.width, size.height) * 0.46;
    const stroke = 14.0;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = sun ? const Color(0x33000000) : const Color(0x33FFFFFF);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      _start,
      _sweep,
      false,
      track,
    );

    final fillT = _t(value);
    if (fillT > 0) {
      final fill = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: radius),
        _start,
        _sweep * fillT,
        false,
        fill,
      );
    }

    final tickPaint = Paint()
      ..strokeWidth = 1.4
      ..color = sun ? const Color(0x99000000) : const Color(0x66FFFFFF);
    for (var i = 0; i <= 10; i++) {
      final a = _start + _sweep * (i / 10);
      final inner = radius - stroke / 2 - (i % 5 == 0 ? 10 : 6);
      final outer = radius - stroke / 2 - 2;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * inner,
        c + Offset(math.cos(a), math.sin(a)) * outer,
        tickPaint,
      );
    }

    final red = redline;
    if (red != null && red >= min && red <= max) {
      final a = _start + _sweep * _t(red);
      final redPaint = Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = sun ? AppColors.sunCrimson : AppColors.crimson;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (radius - stroke / 2 - 16),
        c + Offset(math.cos(a), math.sin(a)) * (radius + stroke / 2 + 4),
        redPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GaugePainter old) =>
      old.value != value ||
      old.redline != redline ||
      old.color != color ||
      old.sun != sun ||
      old.min != min ||
      old.max != max;
}
