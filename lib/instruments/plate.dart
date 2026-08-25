import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../fonts.dart';

const String kDriverPlateKey = 'driver_plate';
const String kDefaultPlate = 'KK4181R';

String normalizePlate(String raw) {
  final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return cleaned.length > 8 ? cleaned.substring(0, 8) : cleaned;
}

/// Kraków-style EU plate: blue band + reflective field + condensed black marks.
class LicensePlate extends StatelessWidget {
  const LicensePlate({
    super.key,
    required this.text,
    this.height = 28,
    this.compact = false,
  });

  final String text;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final plate = normalizePlate(text).isEmpty
        ? kDefaultPlate
        : normalizePlate(text);
    final h = height;
    final r = h * 0.16;
    return Semantics(
      label: plate,
      child: SizedBox(
        height: h,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF4F1E4),
            borderRadius: BorderRadius.circular(r),
            border: Border.all(color: const Color(0xFF1A1A1A), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(r - 0.4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: h * 0.42,
                  color: const Color(0xFF003399),
                  alignment: Alignment.center,
                  child: Text(
                    'PL',
                    style: TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: h * 0.32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: h * 0.18),
                  child: Text(
                    plate,
                    style: TextStyle(
                      fontFamily: AppFonts.jetBrainsMono,
                      fontSize: compact ? h * 0.48 : h * 0.52,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111111),
                      letterSpacing: 1.6,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final next = normalizePlate(newValue.text);
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }
}
