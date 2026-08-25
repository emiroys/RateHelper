import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_text_styles.dart';
import '../fonts.dart';

/// 24-hour radial clock of accepted vs rejected overlay taps.
class ShiftClock extends StatelessWidget {
  const ShiftClock({
    super.key,
    required this.taps,
    this.sun = false,
    this.size = 220,
  });

  final List<Map<String, dynamic>> taps;
  final bool sun;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accepted = List<int>.filled(24, 0);
    final rejected = List<int>.filled(24, 0);
    for (final t in taps) {
      final raw = t['timestamp'];
      DateTime? dt;
      if (raw is String) dt = DateTime.tryParse(raw);
      if (dt == null) continue;
      final hour = dt.hour.clamp(0, 23);
      final type = '${t['type']}'.toLowerCase();
      if (type.contains('reject')) {
        rejected[hour]++;
      } else {
        accepted[hour]++;
      }
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShiftClockPainter(
          accepted: accepted,
          rejected: rejected,
          sun: sun,
        ),
      ),
    );
  }
}

class _ShiftClockPainter extends CustomPainter {
  _ShiftClockPainter({
    required this.accepted,
    required this.rejected,
    required this.sun,
  });

  final List<int> accepted;
  final List<int> rejected;
  final bool sun;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 8;
    var peak = 1;
    for (var h = 0; h < 24; h++) {
      peak = math.max(peak, accepted[h] + rejected[h]);
    }

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = sun ? const Color(0x33000000) : const Color(0x33FFFFFF);
    canvas.drawCircle(c, r, track);

    const slice = 2 * math.pi / 24;
    const start = -math.pi / 2;
    for (var h = 0; h < 24; h++) {
      final a0 = start + slice * h + 0.02;
      final sweep = slice - 0.04;
      final acc = accepted[h] / peak;
      final rej = rejected[h] / peak;
      if (acc > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * (0.35 + 0.65 * acc)),
          a0,
          sweep,
          true,
          Paint()
            ..color = (sun ? AppColors.sunEmerald : AppColors.emerald)
                .withValues(alpha: 0.85),
        );
      }
      if (rej > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * (0.35 + 0.65 * rej)),
          a0,
          sweep,
          true,
          Paint()
            ..color = (sun ? AppColors.sunCrimson : AppColors.crimson)
                .withValues(alpha: 0.55),
        );
      }
    }

    final labelPaint = TextPainter(textDirection: TextDirection.ltr);
    for (final h in [0, 6, 12, 18]) {
      final a = start + slice * h;
      final pos = c + Offset(math.cos(a), math.sin(a)) * (r + 2);
      labelPaint.text = TextSpan(
        text: h.toString().padLeft(2, '0'),
        style: T.micro.copyWith(color: sun ? AppColors.sunInk : Colors.white, fontWeight: FontWeight.w700, fontFamily: AppFonts.jetBrainsMono),
      );
      labelPaint.layout();
      labelPaint.paint(
        canvas,
        pos - Offset(labelPaint.width / 2, labelPaint.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShiftClockPainter old) =>
      old.sun != sun ||
      !_listEq(old.accepted, accepted) ||
      !_listEq(old.rejected, rejected);

  bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
