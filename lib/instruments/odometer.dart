import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../fonts.dart';

/// Mechanical digit-roll display. Digits only animate when [value] changes.
class Odometer extends StatelessWidget {
  const Odometer({
    super.key,
    required this.value,
    this.digits = 4,
    this.sun = false,
    this.digitHeight = 28,
  });

  final int value;
  final int digits;
  final bool sun;
  final double digitHeight;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0, 999999);
    final raw = clamped.toString().padLeft(digits, '0');
    final chars = raw.substring(raw.length - digits);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chars.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          _DigitReel(
            digit: int.parse(chars[i]),
            sun: sun,
            height: digitHeight,
          ),
        ],
      ],
    );
  }
}

class _DigitReel extends StatefulWidget {
  const _DigitReel({
    required this.digit,
    required this.sun,
    required this.height,
  });

  final int digit;
  final bool sun;
  final double height;

  @override
  State<_DigitReel> createState() => _DigitReelState();
}

class _DigitReelState extends State<_DigitReel> {
  late int _from;

  @override
  void initState() {
    super.initState();
    _from = widget.digit;
  }

  @override
  void didUpdateWidget(covariant _DigitReel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.digit != widget.digit) _from = oldWidget.digit;
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.sun ? const Color(0xFF1A1A1A) : const Color(0xFF0A0A0A);
    final ink = widget.sun ? const Color(0xFFF2F2F2) : Colors.white;
    final height = widget.height;
    return Container(
      width: height * 0.72,
      height: height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppColors.borderFor(widget.sun)),
      ),
      clipBehavior: Clip.antiAlias,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: _from.toDouble(),
          end: widget.digit.toDouble(),
        ),
        duration: _from == widget.digit
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) {
          return Stack(
            children: [
              for (var n = 0; n <= 9; n++)
                Transform.translate(
                  offset: Offset(0, (n - v) * height),
                  child: SizedBox(
                    height: height,
                    child: Center(
                      child: Text(
                        '$n',
                        style: TextStyle(
                          fontFamily: AppFonts.jetBrainsMono,
                          fontSize: height * 0.62,
                          fontWeight: FontWeight.w700,
                          color: ink,
                          height: 1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
