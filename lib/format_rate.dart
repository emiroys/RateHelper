import 'l10n.dart';

/// One-decimal percent with trailing zeros dropped — the overlay's format,
/// shared so home and the pill never disagree.
String formatRatePercent(double rate) {
  if (rate.isNaN || rate.isInfinite) return S.formatPercent('100');
  final rounded = (rate * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) {
    return S.formatPercent(rounded.toInt().toString());
  }
  return S.formatPercent(rounded.toStringAsFixed(1));
}
