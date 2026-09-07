import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rate_helper/fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'app_widgets.dart';
import 'earnings_models.dart';
import 'earnings_pdf_export.dart';
import 'instruments/bezel.dart';
import 'instruments/load_meter.dart';
import 'instruments/odometer.dart';
import 'instruments/plate.dart';
import 'l10n.dart';
import 'log.dart';

const kDriverNameKey = 'driver_name';

const _cardColor = AppColors.card;
const _emerald = AppColors.emerald;
const _crimson = AppColors.crimson;
const _amber = AppColors.amber;
final _cardBorder = kCardBorder;
final _cardRadius = kCardBorderRadius;

/// PLN/hour above which the hourly rate is considered "good" (green).
const double _goodHourlyThreshold = 30.0;

/// Gold accent used for the record badges.
const _gold = AppColors.gold;

/// Minimum tap area for controls used while driving.
const double _kMinTouchTarget = kMinTouchTarget;

/// Chart / summary granularity selectable from the segmented control.
enum _ViewMode { weekly, monthly, yearly }

/// Max number of weeks shown in the weekly trend chart. Fixed so the chart's
/// width/layout never grows as more history accumulates â€” older weeks stay
/// reachable via the history list below instead.
const int _trendWeekWindow = 8;

Future<void> showDriverModeDialog(
  BuildContext context,
  SharedPreferences prefs,
  VoidCallback onModeChanged,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: AppColors.base,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          S.driverModeDialogTitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: T.titleLg,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: activeDriverMode == DriverMode.solo
                  ? AppColors.raised
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.person_rounded,
                  color: activeDriverMode == DriverMode.solo
                      ? _amber
                      : AppColors.mutedText,
                ),
                title: Text(
                  S.driverModeSolo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.titleXs.copyWith(fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  activeDriverMode = DriverMode.solo;
                  await prefs.setString(DriverMode.key, 'solo');
                  await prefs.setBool(DriverMode.askedKey, true);
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  onModeChanged();
                },
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: activeDriverMode == DriverMode.paired
                  ? AppColors.raised
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.people_rounded,
                  color: activeDriverMode == DriverMode.paired
                      ? _amber
                      : AppColors.mutedText,
                ),
                title: Text(
                  S.driverModePaired,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.titleXs.copyWith(fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  activeDriverMode = DriverMode.paired;
                  await prefs.setString(DriverMode.key, 'paired');
                  await prefs.setBool(DriverMode.askedKey, true);
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  onModeChanged();
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

String _monthTitle(DateTime month) =>
    '${S.monthsFull[month.month]} ${month.year}';

String _weekRangeLabel(DateTime start, DateTime end) {
  final months = S.months;
  if (start.month == end.month) {
    return '${start.day}-${end.day} ${months[end.month]}';
  }
  return '${start.day} ${months[start.month]} - ${end.day} ${months[end.month]}';
}

Color _hourlyColor(double rate) =>
    rate >= _goodHourlyThreshold ? _emerald : (rate > 0 ? _amber : _crimson);

/// Live PLN input: thousand dots + decimal comma, JetBrains-friendly digits.
class _PlnInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(RegExp(r'[^0-9,]'), '');
    if (raw.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final parts = raw.split(',');
    var intDigits = parts.first.replaceAll(RegExp(r'[^0-9]'), '');
    var decDigits = parts.length > 1
        ? parts.sublist(1).join().replaceAll(RegExp(r'[^0-9]'), '')
        : null;
    if (intDigits.length > 6) intDigits = intDigits.substring(0, 6);
    if (decDigits != null && decDigits.length > 2) {
      decDigits = decDigits.substring(0, 2);
    }
    final grouped = StringBuffer();
    for (var i = 0; i < intDigits.length; i++) {
      if (i > 0 && (intDigits.length - i) % 3 == 0) grouped.write('\u00A0');
      grouped.write(intDigits[i]);
    }
    final text = decDigits == null
        ? (raw.contains(',') ? '$grouped,' : grouped.toString())
        : '$grouped,$decDigits';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Localized text for an informational cross-check warning.
String _warningText(EarningsWarning w) {
  switch (w) {
    case EarningsWarning.hourlyRate:
      return S.warnHourlyRate;
  }
}

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({
    super.key,
    this.autoAddWeek = false,
    this.autoQuickFuel = false,
  });

  /// When true, the "add new week" form for the current week opens
  /// automatically after the first load.
  final bool autoAddWeek;

  /// When true, opens the quick-add-fuel dialog after the first load.
  final bool autoQuickFuel;

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  SharedPreferences? _prefs;
  List<WeekEarning> _entries = [];

  /// Monthly / yearly rollups, memoized so [aggregateByMonth]/[aggregateByYear]
  /// (which walk up to 104 weeks) run once per data change instead of on every
  /// frame/rebuild. Recomputed only in [_setEntries].
  List<MonthSummary> _months = const [];
  List<YearSummary> _years = const [];

  bool _loading = true;

  /// True while a PDF report is being built and handed to the share sheet.
  bool _exporting = false;
  int _weekOffset = 0;
  String _driverName = '';
  String? _celebrateBestId;

  _ViewMode _viewMode = _ViewMode.weekly;

  /// First day of the month currently focused in the monthly view.
  DateTime? _selectedMonth;

  /// First day of the month selected in the weekly view history filter.
  DateTime? _historyFilterMonth;

  /// Year currently focused in the yearly view.
  int? _selectedYear;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _rowKeys = {};

  GlobalKey _keyForEntry(WeekEarning e) =>
      _rowKeys.putIfAbsent(e.id, () => GlobalKey());

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Selects [entry]'s week (highlighting its card + history row) and scrolls
  /// the matching history row into view. Used by both history taps and the
  /// trend chart bars.
  void _selectWeek(WeekEarning entry) {
    HapticFeedback.selectionClick();
    setState(() => _weekOffset = _offsetForEntry(entry));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKeys[entry.id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      }
    });
  }

  Future<void> _load() async {
    final prefs = await _getPrefs();
    await prefs.reload();
    final entries = decodeEarnings(
      prefs.getString(kEarningsHistoryKey),
      onCorrupt: (raw) => prefs.setString(kEarningsCorruptBackupKey, raw),
    )..sort((a, b) => b.weekStart.compareTo(a.weekStart));
    if (!mounted) return;
    if (entries.isNotEmpty) {
      final latest = entries.first.weekStart;
      _historyFilterMonth ??= DateTime(latest.year, latest.month, 1);
    }
    final modeStr = prefs.getString(DriverMode.key);
    activeDriverMode = modeStr == 'paired'
        ? DriverMode.paired
        : DriverMode.solo;

    // --- Lifetime trip odometer migration & load ---
    // One-time backfill: seed the persisted counter from whatever history
    // currently exists. Weeks already evicted by FIFO before this update are
    // permanently uncounted â€” the same limitation as before, just frozen.
    if (prefs.getBool(kLifetimeTripsBackfilledKey) != true) {
      final backfill = calculateLifetimeTrips(entries);
      await prefs.setInt(kLifetimeTripsKey, backfill);
      await prefs.setBool(kLifetimeTripsBackfilledKey, true);
    }
    _cachedLifetimeTrips = prefs.getInt(kLifetimeTripsKey) ?? 0;

    setState(() {
      _setEntries(entries);
      _driverName = prefs.getString(kDriverNameKey) ?? '';
      _loading = false;
    });

    if (prefs.getBool(DriverMode.askedKey) != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && prefs.getBool(DriverMode.askedKey) != true) {
          showDriverModeDialog(context, prefs, () {
            if (mounted) setState(() {});
          });
        }
      });
    }

    if (widget.autoAddWeek && !_autoAddTriggered) {
      _autoAddTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final start = weekStartForOffset(0);
        _openForm(
          existing: _entryForOffset(0),
          start: start,
          end: weekEndForStart(start),
        );
      });
    }

    if (widget.autoQuickFuel && !_autoFuelTriggered) {
      _autoFuelTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_quickAddFuel());
      });
    }
  }

  /// Guards against re-opening the auto-add form on every reload.
  bool _autoAddTriggered = false;
  bool _autoFuelTriggered = false;

  int _cachedLifetimeTrips = 0;

  List<WeekEarning> _trend = const [];
  List<DateTime> _histMonths = const [];

  /// Replaces the entry list and refreshes the memoized monthly/yearly rollups.
  /// The only place [_entries] should be reassigned, so the caches never drift.
  /// Note: _cachedLifetimeTrips is NOT recomputed here â€” it is loaded from the
  /// persisted SharedPreferences odometer and updated only on new/edited saves.
  void _setEntries(List<WeekEarning> entries) {
    _entries = entries;
    _rowKeys.removeWhere((id, _) => !entries.any((e) => e.id == id));
    _months = aggregateByMonth(entries);
    _years = aggregateByYear(entries);
    _trend = _computeTrendWeeks(entries);
    _histMonths = _computeHistoryMonths(entries);
  }

  /// Distinct calendar months present in [_entries], oldest â†’ newest.
  List<DateTime> _computeHistoryMonths(List<WeekEarning> entries) {
    final seen = <String, DateTime>{};
    for (final e in entries) {
      final key = '${e.weekStart.year}-${e.weekStart.month}';
      seen.putIfAbsent(
        key,
        () => DateTime(e.weekStart.year, e.weekStart.month, 1),
      );
    }
    return seen.values.toList()..sort((a, b) => a.compareTo(b));
  }

  /// Resolves the active history month, defaulting to the latest record.
  DateTime? _activeHistoryMonth() {
    final months = _histMonths;
    if (months.isEmpty) return null;
    final selected = _historyFilterMonth;
    if (selected != null) {
      for (final m in months) {
        if (m.year == selected.year && m.month == selected.month) return m;
      }
    }
    return months.last;
  }

  /// Weekly records for the active history month filter.
  List<WeekEarning> _filteredHistoryEntries() {
    final month = _activeHistoryMonth();
    if (month == null) return [];
    return _entries
        .where(
          (e) =>
              e.weekStart.year == month.year &&
              e.weekStart.month == month.month,
        )
        .toList();
  }

  Future<void> _persist() async {
    final prefs = await _getPrefs();
    await prefs.setString(kEarningsHistoryKey, encodeEarnings(_entries));
  }

  /// Atomically increments the persisted lifetime trip odometer by [delta]
  /// and updates the in-memory cache.
  Future<void> _incrementLifetimeTrips(int delta) async {
    if (delta <= 0) return;
    final prefs = await _getPrefs();
    final current = prefs.getInt(kLifetimeTripsKey) ?? 0;
    final next = current + delta;
    await prefs.setInt(kLifetimeTripsKey, next);
    if (mounted) {
      setState(() => _cachedLifetimeTrips = next);
    }
  }

  Future<void> _resetLifetimeTrips() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.mdRadius,
        ),
        title: Text(
          S.resetLifetimeTripsTitle,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          S.resetLifetimeTripsConfirm,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: AppColors.mutedText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              S.cancel,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: AppColors.mutedText,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              S.resetLifetimeTrips,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: _crimson,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await _getPrefs();
      await prefs.setInt(kLifetimeTripsKey, 0);
      if (mounted) {
        setState(() => _cachedLifetimeTrips = 0);
      }
    }
  }

  Future<void> _editLifetimeTrips() async {
    final controller = TextEditingController(
      text: _cachedLifetimeTrips.toString(),
    );
    int? newCount;
    try {
      newCount = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.mdRadius,
          ),
          title: Text(
            S.editLifetimeTripsTitle,
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  S.editLifetimeTripsDesc,
                  style: T.label.copyWith(height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    labelText: S.editLifetimeTripsLabel,
                    labelStyle: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: AppColors.mutedText,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.disabledText),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: _gold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                S.cancel,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: AppColors.mutedText,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed != null && parsed >= 0) {
                  Navigator.pop(context, parsed);
                } else {
                  Navigator.pop(context);
                }
              },
              child: Text(
                S.save,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: _gold,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (newCount != null) {
      final prefs = await _getPrefs();
      await prefs.setInt(kLifetimeTripsKey, newCount);
      if (mounted) {
        setState(() => _cachedLifetimeTrips = newCount!);
      }
    }
  }

  WeekEarning? _entryForOffset(int offset) {
    final start = weekStartForOffset(offset);
    for (final e in _entries) {
      if (isSameDate(e.weekStart, start)) return e;
    }
    return null;
  }

  int _offsetForEntry(WeekEarning entry) {
    final currentMonday = weekStartForOffset(0);
    final diff = entry.weekStart.difference(currentMonday).inDays;
    return (diff / 7).round();
  }

  /// Up to the last [_trendWeekWindow] recorded weeks, ordered oldest â†’ newest
  /// for the chart. [_entries] is kept newest-first, so reverse it to
  /// chronological order first, then keep only the trailing (most recent)
  /// slice â€” this caps the chart to a fixed window so it never grows wider as
  /// more weeks accumulate, mirroring the 12-item cap on the monthly/yearly
  /// charts.
  List<WeekEarning> _computeTrendWeeks(List<WeekEarning> entries) {
    final weeks = entries.reversed.toList();
    return weeks.length > _trendWeekWindow
        ? weeks.sublist(weeks.length - _trendWeekWindow)
        : weeks;
  }

  Future<void> _openForm({
    WeekEarning? existing,
    required DateTime start,
    required DateTime end,
  }) async {
    final result = await Navigator.of(context).push<WeekEarning>(
      MaterialPageRoute<WeekEarning>(
        builder: (_) => _EarningsFormScreen(
          existing: existing,
          weekStart: start,
          weekEnd: end,
        ),
      ),
    );
    if (result == null) return;
    final others = _entries.where((e) => e.id != result.id).toList();
    final prevBest = bestHourlyRateWeek(others);
    final isNewBest = result.hourlyRate > 0 &&
        (prevBest == null || result.hourlyRate > prevBest.hourlyRate);
    final oldTrips = existing?.driverTripCount ?? 0;
    final tripDelta = result.driverTripCount - oldTrips;
    setState(() {
      final next = [..._entries]
        ..removeWhere(
          (e) => e.id == result.id || isSameDate(e.weekStart, result.weekStart),
        )
        ..add(result)
        ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
      _setEntries(next);
      if (isNewBest) _celebrateBestId = result.id;
    });
    if (isNewBest) HapticFeedback.heavyImpact();
    await _persist();
    if (tripDelta > 0) {
      await _incrementLifetimeTrips(tripDelta);
    }
  }

  Future<void> _deleteEntry(WeekEarning entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          S.delete,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          S.deleteWeekConfirm,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: AppColors.mutedText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              S.cancel,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: AppColors.mutedText,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              S.delete,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: _crimson,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _setEntries([..._entries]..removeWhere((e) => e.id == entry.id));
    });
    await _persist();
  }

  bool _fuelDialogActive = false;

  Future<void> _quickAddFuel() async {
    if (_fuelDialogActive) return;
    _fuelDialogActive = true;
    final ctrl = TextEditingController();
    double? added;
    try {
      added = await showDialog<double>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.mdRadius,
            ),
            title: Text(
              S.quickAddFuelTitle,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: T.titleLg,
              autofocus: true,
              decoration: InputDecoration(
                labelText: S.amountPaidLabel,
                labelStyle: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: AppColors.mutedText,
                ),
                suffixText: 'PLN',
                suffixStyle: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: _amber,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.hairlineStrong),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: _amber),
                ),
              ),
              onSubmitted: (_) {
                final val = double.tryParse(
                  ctrl.text.replaceAll(',', '.').trim(),
                );
                if (val != null && val > 0) {
                  Navigator.of(ctx).pop(val);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  S.cancel,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: AppColors.mutedText,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final val = double.tryParse(
                    ctrl.text.replaceAll(',', '.').trim(),
                  );
                  if (val != null && val > 0) {
                    Navigator.of(ctx).pop(val);
                  }
                },
                child: Text(
                  S.add,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
      _fuelDialogActive = false;
    }

    if (added == null || added <= 0 || !mounted) return;

    final currentMonday = weekStartForOffset(0);
    final currentSunday = weekEndForStart(currentMonday);

    WeekEarning? currentEntry;
    for (final e in _entries) {
      if (isSameDate(e.weekStart, currentMonday)) {
        currentEntry = e;
        break;
      }
    }

    final newReceipt = FuelReceipt(
      timestamp: DateTime.now(),
      amountPaid: added,
    );

    WeekEarning nextEntry;
    if (currentEntry != null) {
      nextEntry = currentEntry.copyWith(
        fuelReceipts: capFuelReceipts([
          ...currentEntry.fuelReceipts,
          newReceipt,
        ]),
      );
    } else {
      nextEntry = WeekEarning(
        id: '${currentMonday.millisecondsSinceEpoch}_${currentSunday.millisecondsSinceEpoch}',
        weekStart: currentMonday,
        weekEnd: currentSunday,
        driverMode: activeDriverMode,
        netIncome: 0,
        cashReceived: 0,
        onlineHours: 0,
        driverTripCount: 0,
        hasRentalDiscount: true,
        fuelReceipts: [newReceipt],
      );
    }

    setState(() {
      final nextList = [..._entries]
        ..removeWhere(
          (e) =>
              e.id == nextEntry.id ||
              isSameDate(e.weekStart, nextEntry.weekStart),
        )
        ..add(nextEntry)
        ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
      _setEntries(nextList);
    });
    await _persist();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.raised,
        behavior: SnackBarBehavior.floating,
        content: Text(
          S.fuelAddedConfirmation(
            formatPln(added),
            nextEntry.fuelReceipts.length,
          ),
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _deleteReceiptFromEntry(
    WeekEarning entry,
    String receiptId,
  ) async {
    final idx = entry.fuelReceipts.indexWhere((r) => r.id == receiptId);
    if (idx < 0) return;
    final removedReceipt = entry.fuelReceipts[idx];
    final nextReceipts = entry.fuelReceipts
        .where((r) => r.id != receiptId)
        .toList();
    final nextEntry = entry.copyWith(fuelReceipts: nextReceipts);
    setState(() {
      final nextList = [..._entries]
        ..removeWhere(
          (e) =>
              e.id == nextEntry.id ||
              isSameDate(e.weekStart, nextEntry.weekStart),
        )
        ..add(nextEntry)
        ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
      _setEntries(nextList);
    });
    await _persist();

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(S.receiptDeleted),
        action: SnackBarAction(
          label: S.undo,
          onPressed: () async {
            final restoredReceipts = [...nextEntry.fuelReceipts];
            final insertAt = idx.clamp(0, restoredReceipts.length);
            restoredReceipts.insert(insertAt, removedReceipt);
            final restoredEntry = nextEntry.copyWith(
              fuelReceipts: capFuelReceipts(restoredReceipts),
            );
            setState(() {
              final restoredList = [..._entries]
                ..removeWhere(
                  (e) =>
                      e.id == restoredEntry.id ||
                      isSameDate(e.weekStart, restoredEntry.weekStart),
                )
                ..add(restoredEntry)
                ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
              _setEntries(restoredList);
            });
            await _persist();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sun = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor: AppColors.scaffold(sun),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _quickAddFuel,
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.local_gas_station_rounded),
        label: Text(
          S.quickAddFuel,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: AppColors.scaffold(
          Theme.of(context).brightness == Brightness.light,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          S.earningsTitle,
          style: T.titleMd,
        ),
        actions: [
          IconButton(
            tooltip: S.exportPdf,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: _emerald,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
            onPressed: _entries.isEmpty || _exporting ? null : _exportPdf,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator(color: _emerald))
          else
            SafeArea(
              top: false,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: _buildSlivers(),
              ),
            ),
          // Building and sharing the PDF can take a couple of seconds (font
          // loading + rasterisation); block input and show progress so the
          // screen never looks frozen.
          if (_exporting)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.7),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: _emerald),
                      const SizedBox(height: 18),
                      Text(
                        S.exportPdfInProgress,
                        textAlign: TextAlign.center,
                        style: T.titleXs.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Shows the "Ad Soyad" text-field dialog, saves the entered name to
  /// SharedPreferences, and returns it. Returns null if the user dismisses
  /// the dialog without saving (dismissed prompts never block PDF export â€”
  /// callers proceed with an empty name, which the PDF header renders as a
  /// generic placeholder).
  Future<String?> _editDriverName() async {
    final controller = TextEditingController(text: _driverName);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            S.driverNamePrompt,
            style: T.titleXs,
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: T.titleSm,
            decoration: InputDecoration(
              labelText: S.driverNameLabel,
              labelStyle: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: AppColors.mutedText,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.hairlineStrong),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: _emerald, width: 1.5),
              ),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: Text(
                S.driverNameContinue,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: _emerald,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
      if (result == null) return null;

      final prefs = await _getPrefs();
      await prefs.setString(kDriverNameKey, result);
      if (mounted) setState(() => _driverName = result);
      return result;
    } finally {
      controller.dispose();
    }
  }

  /// Prompts for a range (Bu Ay / Bu YÄ±l / TÃ¼m Zamanlar), then builds and
  /// shares a plain PDF earnings report for the weeks in that range.
  Future<void> _exportPdf() async {
    final choice = await showModalBottomSheet<_ExportRange>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: AppSheetHandle()),
            const SizedBox(height: 18),
            Text(
              S.exportPdfRangeTitle,
              style: T.sectionHeader,
            ),
            const SizedBox(height: 14),
            _RangeOption(
              label: S.rangeThisMonth,
              onTap: () => Navigator.of(ctx).pop(_ExportRange.thisMonth),
            ),
            const SizedBox(height: 10),
            _RangeOption(
              label: S.rangeSpecificMonth,
              onTap: () => Navigator.of(ctx).pop(_ExportRange.specificMonth),
            ),
            const SizedBox(height: 10),
            _RangeOption(
              label: S.rangeThisYear,
              onTap: () => Navigator.of(ctx).pop(_ExportRange.thisYear),
            ),
            const SizedBox(height: 10),
            _RangeOption(
              label: S.rangeAllTime,
              onTap: () => Navigator.of(ctx).pop(_ExportRange.allTime),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    final now = DateTime.now();
    final List<WeekEarning> weeks;
    final String rangeLabel;
    switch (choice) {
      case _ExportRange.thisMonth:
        // Reuse aggregateByMonth's bucketing (via weeksForMonth) so "Bu Ay"
        // stays perfectly in sync with the monthly view and the week-belongs-
        // to-its-weekStart-month rule â€” no separate ad-hoc filter to drift.
        weeks = EarningsPdfExport.weeksForMonth(
          _entries,
          DateTime(now.year, now.month, 1),
        );
        rangeLabel = S.rangeThisMonth;
      case _ExportRange.specificMonth:
        final picked = await _pickExportMonth();
        if (picked == null || !mounted) return;
        weeks = EarningsPdfExport.weeksForMonth(_entries, picked);
        rangeLabel = _monthTitle(picked);
      case _ExportRange.thisYear:
        weeks = _entries.where((e) => e.weekStart.year == now.year).toList();
        rangeLabel = S.rangeThisYear;
      case _ExportRange.allTime:
        weeks = [..._entries];
        rangeLabel = S.rangeAllTime;
    }

    if (weeks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.exportNoData), backgroundColor: _cardColor),
      );
      return;
    }

    var driverName = _driverName;
    if (driverName.trim().isEmpty) {
      driverName = await _editDriverName() ?? '';
      if (!mounted) return;
    }

    setState(() => _exporting = true);
    try {
      await EarningsPdfExport.generateAndShare(
        weeks,
        rangeLabel: rangeLabel,
        driverName: driverName,
        plate: (await SharedPreferences.getInstance())
                .getString(kDriverPlateKey) ??
            '',
      );
    } catch (e, s) {
      loge('pdf export failed', name: 'earnings', error: e, stack: s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.exportFailed), backgroundColor: _cardColor),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Bottom sheet listing every month that actually has recorded weeks (from the
  /// memoized [_months] rollup), newest first, e.g. "Haziran 2026". Returns the
  /// first-of-month [DateTime] the user picks, or null if dismissed.
  Future<DateTime?> _pickExportMonth() {
    final monthsNewestFirst = _months.reversed.toList();
    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppSheetHandle()),
              const SizedBox(height: 18),
              Text(
                S.exportPickMonthTitle,
                style: T.sectionHeader,
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final m in monthsNewestFirst) ...[
                        _RangeOption(
                          label: _monthTitle(m.month),
                          onTap: () => Navigator.of(ctx).pop(m.month),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSlivers() {
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _DriverNameRow(
                  name: _driverName,
                  onTap: _editDriverName,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      final prefs = await _getPrefs();
                      if (!mounted) return;
                      await showDriverModeDialog(context, prefs, () {
                        if (mounted) setState(() {});
                      });
                    },
                    child: SizedBox(
                      height: _kMinTouchTarget,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.raised,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.disabledText),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  S.driverModeLabel(
                                    activeDriverMode == DriverMode.paired,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.captionSm.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.edit_rounded,
                                size: 14,
                                color: AppColors.labelText,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _FreeWeekProgressCard(
            lifetimeTrips: _cachedLifetimeTrips,
            onReset: _resetLifetimeTrips,
            onEdit: _editLifetimeTrips,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _ViewToggle(
            mode: _viewMode,
            onChanged: (m) => setState(() => _viewMode = m),
          ),
        ),
      ),
    ];

    switch (_viewMode) {
      case _ViewMode.weekly:
        slivers.addAll(_weeklySlivers());
      case _ViewMode.monthly:
        slivers.addAll(_monthlySlivers());
      case _ViewMode.yearly:
        slivers.addAll(_yearlySlivers());
    }
    return slivers;
  }

  /// Best-week records card, shown in the monthly view below the chart. Receives
  /// only the currently selected month's weeks so it re-filters with selection.
  Widget _recordsSliver(List<WeekEarning> weeks) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _RecordsCard(
            weeks: weeks,
            celebrateId: _celebrateBestId,
            onCelebrateDone: () {
              if (mounted) setState(() => _celebrateBestId = null);
            },
          ),
        ),
      );

  List<Widget> _weeklySlivers() {
    final start = weekStartForOffset(_weekOffset);
    final end = weekEndForStart(start);
    final entry = _entryForOffset(_weekOffset);
    final canGoForward = _weekOffset < 0;
    final filteredHistory = _filteredHistoryEntries();
    final activeHistoryMonth = _activeHistoryMonth();
    final trend = _trend;

    return [
      if (trend.length >= 2)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _TrendChart(
              weeks: trend,
              selectedStart: start,
              onBarTap: _selectWeek,
            ),
          ),
        )
      // A single recorded week cannot form a trend line. Say so explicitly
      // instead of silently leaving a gap where the chart will appear.
      else if (_entries.isNotEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _TrendPlaceholder(),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _WeekSelector(
            label: _weekRangeLabel(start, end),
            canGoForward: canGoForward,
            onPrev: () => setState(() => _weekOffset -= 1),
            onNext: canGoForward
                ? () => setState(() => _weekOffset += 1)
                : null,
          ),
        ),
      ),
      if (entry != null) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _HeroCard(entry: entry),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _BreakdownCard(
              entry: entry,
              onDeleteReceipt: (receiptId) =>
                  _deleteReceiptFromEntry(entry, receiptId),
              // Break-even uses THIS week's own fuel + rental, never a
              // historical average â€” consistent with the live entry-form
              // preview and every other fuel figure in the app.
              breakEven: calculateBreakEven(
                fixedCosts: entry.fuelAfterDiscount + entry.rentalFee,
              ),
            ),
          ),
        ),
        if (entry.warnings.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _WarningList(warnings: entry.warnings),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: S.edit,
                    icon: Icons.edit_rounded,
                    filled: false,
                    onTap: () =>
                        _openForm(existing: entry, start: start, end: end),
                  ),
                ),
                const SizedBox(width: 12),
                _IconOnlyButton(
                  icon: Icons.delete_outline_rounded,
                  color: _crimson,
                  onTap: () => _deleteEntry(entry),
                ),
              ],
            ),
          ),
        ),
      ] else
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _EmptyWeekCard(
              onAdd: () => _openForm(start: start, end: end),
            ),
          ),
        ),
      // With no saved weeks at all the empty week card above already tells the
      // whole story â€” an extra "HISTORY / no data" block would just repeat it.
      if (_entries.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              S.history,
              style: T.sectionHeader,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: _HistoryMonthSelector(
              months: _histMonths,
              selected: activeHistoryMonth!,
              onSelected: (m) {
                HapticFeedback.selectionClick();
                setState(() => _historyFilterMonth = m);
              },
            ),
          ),
        ),
        if (filteredHistory.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: _EmptyPanel(
                icon: Icons.calendar_month_rounded,
                title: S.history,
                description: S.bestWeekEmpty,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList.builder(
              itemCount: filteredHistory.length,
              itemBuilder: (context, i) {
                final e = filteredHistory[i];
                return RepaintBoundary(
                  key: _keyForEntry(e),
                  child: _HistoryRow(
                    entry: e,
                    rangeLabel: _weekRangeLabel(e.weekStart, e.weekEnd),
                    selected: isSameDate(e.weekStart, start),
                    onTap: () => _selectWeek(e),
                  ),
                );
              },
            ),
          ),
      ],
    ];
  }

  List<Widget> _monthlySlivers() {
    final all = _months;
    if (all.isEmpty) return [_emptyStateSliver()];

    final recent = all.length > 12 ? all.sublist(all.length - 12) : all;
    var selected = recent.last;
    if (_selectedMonth != null) {
      for (final m in recent) {
        if (m.month.year == _selectedMonth!.year &&
            m.month.month == _selectedMonth!.month) {
          selected = m;
          break;
        }
      }
    }

    final maxRate = recent.fold<double>(
      0,
      (m, s) => math.max(m, s.avgHourlyRate),
    );

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: _SummaryCard(
            title: _monthTitle(selected.month),
            totalNetProfit: selected.totalNetProfit,
            avgHourlyRate: selected.avgHourlyRate,
            totalOnlineHours: selected.totalOnlineHours,
            weekCount: selected.weekCount,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _AggregateChart(
            title: S.monthlyTrendTitle,
            bars: [
              for (final m in recent)
                _BarDatum(
                  value: m.avgHourlyRate,
                  heightFactor: maxRate > 0
                      ? (m.avgHourlyRate / maxRate).clamp(0.0, 1.0)
                      : 0,
                  color: _hourlyColor(m.avgHourlyRate),
                  label: S.months[m.month.month],
                  selected:
                      m.month.year == selected.month.year &&
                      m.month.month == selected.month.month,
                  onTap: () => setState(() => _selectedMonth = m.month),
                ),
            ],
          ),
        ),
      ),
      _recordsSliver(selected.weeks),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Text(
            _monthTitle(selected.month).toUpperCase(),
            style: T.sectionHeader,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        sliver: SliverList.builder(
          itemCount: selected.weeks.length,
          itemBuilder: (context, i) {
            final e = selected.weeks[selected.weeks.length - 1 - i];
            return _HistoryRow(
              entry: e,
              rangeLabel: _weekRangeLabel(e.weekStart, e.weekEnd),
              selected: false,
              onTap: () => _jumpToWeek(e),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _yearlySlivers() {
    final years = _years;
    if (years.isEmpty) return [_emptyStateSliver()];

    var selected = years.last;
    if (_selectedYear != null) {
      for (final y in years) {
        if (y.year == _selectedYear) {
          selected = y;
          break;
        }
      }
    }

    final maxRate = years.fold<double>(
      0,
      (m, s) => math.max(m, s.avgHourlyRate),
    );

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: _SummaryCard(
            title: '${selected.year}',
            totalNetProfit: selected.totalNetProfit,
            avgHourlyRate: selected.avgHourlyRate,
            totalOnlineHours: selected.totalOnlineHours,
            weekCount: selected.weekCount,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _AggregateChart(
            title: S.yearlyTrendTitle,
            bars: [
              for (final y in years)
                _BarDatum(
                  value: y.avgHourlyRate,
                  heightFactor: maxRate > 0
                      ? (y.avgHourlyRate / maxRate).clamp(0.0, 1.0)
                      : 0,
                  color: _hourlyColor(y.avgHourlyRate),
                  label: '${y.year}',
                  selected: y.year == selected.year,
                  onTap: () => setState(() => _selectedYear = y.year),
                ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        sliver: SliverList.builder(
          itemCount: selected.months.length,
          itemBuilder: (context, i) {
            final m = selected.months[selected.months.length - 1 - i];
            return _MonthRow(
              summary: m,
              onTap: () => setState(() {
                _viewMode = _ViewMode.monthly;
                _selectedMonth = m.month;
              }),
            );
          },
        ),
      ),
    ];
  }

  /// Switches to the weekly view focused on [entry]'s week.
  void _jumpToWeek(WeekEarning entry) {
    setState(() => _viewMode = _ViewMode.weekly);
    _selectWeek(entry);
  }

  Widget _emptyStateSliver() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: _EmptyWeekCard(
        onAdd: () {
          final start = weekStartForOffset(0);
          _openForm(start: start, end: weekEndForStart(start));
        },
      ),
    ),
  );
}

class _HistoryMonthSelector extends StatelessWidget {
  const _HistoryMonthSelector({
    required this.months,
    required this.selected,
    required this.onSelected,
  });

  final List<DateTime> months;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final showYear = months.map((m) => m.year).toSet().length > 1;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < months.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _HistoryMonthChip(
              label: _label(months[i], showYear),
              selected:
                  months[i].year == selected.year &&
                  months[i].month == selected.month,
              onTap: () => onSelected(months[i]),
            ),
          ],
        ],
      ),
    );
  }

  String _label(DateTime month, bool showYear) {
    final name = S.months[month.month];
    return showYear ? '$name ${month.year}' : name;
  }
}

class _HistoryMonthChip extends StatelessWidget {
  const _HistoryMonthChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? _emerald.withValues(alpha: 0.12)
          : AppColors.hairlineFaint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected
              ? _emerald.withValues(alpha: 0.45)
              : AppColors.hairlineFaint,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: _kMinTouchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.labelStrong.copyWith(
              color: selected ? Colors.white : AppColors.labelText,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small tappable row showing the driver's name for the PDF header, editable
/// anytime. Shows the localized default placeholder when no name is saved
/// yet, so it always reads as an inviting "set your name" affordance.
class _DriverNameRow extends StatelessWidget {
  const _DriverNameRow({required this.name, required this.onTap});

  final String name;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final display = name.trim().isEmpty ? S.driverNameDefault : name.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: _kMinTouchTarget,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  '${S.driverNameLabel}: ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption,
                ),
              ),
              Flexible(
                child: Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.edit_rounded,
                size: 14,
                color: AppColors.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekSelector extends StatelessWidget {
  const _WeekSelector({
    required this.label,
    required this.canGoForward,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final bool canGoForward;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Row(
        children: [
          _arrow(Icons.chevron_left_rounded, true, onPrev),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: T.titleSm.copyWith(letterSpacing: 0.3),
            ),
          ),
          _arrow(Icons.chevron_right_rounded, canGoForward, () {
            onNext?.call();
          }),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, bool enabled, VoidCallback onTap) {
    return Material(
      color: AppColors.hairlineFaint,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            icon,
            size: 30,
            color: enabled ? Colors.white : AppColors.disabledText,
          ),
        ),
      ),
    );
  }
}

/// Animated count-up for hero numbers. On value change it lerps from the
/// previously shown value to the new one over 400ms, formatting each frame
/// with the app's PLN formatter â€” the single highest-impact "alive" touch.
class _CountUp extends StatefulWidget {
  const _CountUp({required this.value, required this.style});

  final double value;
  final TextStyle style;

  @override
  State<_CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<_CountUp> {
  late double _begin;

  @override
  void initState() {
    super.initState();
    _begin = widget.value;
  }

  @override
  void didUpdateWidget(covariant _CountUp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _begin = oldWidget.value;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _begin, end: widget.value),
      duration: _begin == widget.value
          ? Duration.zero
          : const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(formatPln(v), style: widget.style),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.entry});

  final WeekEarning entry;

  @override
  Widget build(BuildContext context) {
    final color = _hourlyColor(entry.hourlyRate);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.hourlyRate,
            style: T.body.copyWith(color: AppColors.labelText, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _CountUp(
                  value: entry.hourlyRate,
                  style: T.heroXLarge.copyWith(color: color),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    S.perHour,
                    style: T.titleSm.copyWith(color: color.withValues(alpha: 0.7), fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningList extends StatelessWidget {
  const _WarningList({required this.warnings});

  final List<EarningsWarning> warnings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _WarningChip(text: _warningText(w)),
          ),
      ],
    );
  }
}

class _WarningChip extends StatelessWidget {
  const _WarningChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Single-line pill; the full message expands in a tap-triggered tooltip so
    // long warnings never wrap or dominate the layout.
    return Tooltip(
      message: text,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 5),
      preferBelow: false,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      textStyle: T.caption.copyWith(color: Colors.white, height: 1.35),
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border.all(color: _amber.withValues(alpha: 0.4), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 16, color: _amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.caption.copyWith(color: _amber),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.weeks,
    required this.selectedStart,
    required this.onBarTap,
  });

  /// Oldest â†’ newest, up to 12 weeks.
  final List<WeekEarning> weeks;
  final DateTime selectedStart;
  final void Function(WeekEarning) onBarTap;

  @override
  Widget build(BuildContext context) {
    final maxProfit = weeks.fold<double>(
      0,
      (m, w) => math.max(m, w.netProfit.abs()),
    );
    final safeMax = maxProfit > 0 ? maxProfit : 1.0;
    final currentStart = weekStartForOffset(0);

    final n = weeks.length;
    final last4 = weeks.sublist(math.max(0, n - 4));
    final prev4 = n > 4
        ? weeks.sublist(math.max(0, n - 8), n - 4)
        : <WeekEarning>[];
    final last4Avg = averageHourlyRate(last4);
    final prev4Avg = averageHourlyRate(prev4);
    final hasTrend = prev4.isNotEmpty && prev4Avg > 0;
    final up = last4Avg >= prev4Avg;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.trendTitle,
            style: T.body.copyWith(color: AppColors.labelText, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  S.fourWeekAverage(formatPln(last4Avg)),
                  style: T.labelStrong.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (hasTrend) ...[
                const SizedBox(width: 8),
                Icon(
                  up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  size: 20,
                  color: up ? _emerald : _crimson,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 148,
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < weeks.length; i++)
                      Expanded(
                        child: _ChartBar(
                          index: i,
                          value: weeks[i].netProfit,
                          heightFactor: (weeks[i].netProfit.abs() / safeMax)
                              .clamp(0.0, 1.0),
                          color: _hourlyColor(weeks[i].hourlyRate),
                          label:
                              '${weeks[i].weekStart.day}.${weeks[i].weekStart.month}',
                          selected:
                              isSameDate(weeks[i].weekStart, selectedStart),
                          ghosted:
                              isSameDate(weeks[i].weekStart, currentStart),
                          onTap: () => onBarTap(weeks[i]),
                        ),
                      ),
                  ],
                ),
                if (safeMax > 0) ...[
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _DashedAvgPainter(
                          fraction: safeMax > 0
                              ? ((last4.isEmpty
                                          ? 0.0
                                          : last4.fold<double>(
                                                  0.0,
                                                  (sum, w) =>
                                                      sum + w.netProfit) /
                                              last4.length) /
                                      safeMax)
                                  .clamp(0.0, 1.0)
                              : 0.0,
                          color: _emerald,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _HourlyOverlayPainter(
                          rates: [for (final w in weeks) w.hourlyRate],
                          maxRate: weeks.fold<double>(
                            1,
                            (m, w) => math.max(m, w.hourlyRate),
                          ),
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
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

/// Shared bar for both the weekly trend and the aggregate (monthly/yearly)
/// charts. Grows its height in with an [index]-staggered cascade (30ms per bar)
/// and paints a topâ†’bottom green gradient with rounded top corners.
class _ChartBar extends StatefulWidget {
  const _ChartBar({
    required this.index,
    required this.value,
    required this.heightFactor,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
    this.ghosted = false,
  });

  final int index;
  final double value;
  final double heightFactor;
  final String label;
  final bool selected;
  final bool ghosted;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ChartBar> createState() => _ChartBarState();
}

class _ChartBarState extends State<_ChartBar> {
  double _target = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 30 * widget.index), () {
      if (mounted) setState(() => _target = widget.heightFactor);
    });
  }

  @override
  void didUpdateWidget(covariant _ChartBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heightFactor != widget.heightFactor) {
      setState(() => _target = widget.heightFactor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final ghosted = widget.ghosted;
    final base = widget.color;
    final topColor = selected
        ? base
        : base.withValues(alpha: ghosted ? 0.18 : 0.45);
    final bottomColor = selected
        ? Color.lerp(base, Colors.black, 0.32)!
        : base.withValues(alpha: 0.12);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: 16,
                child: selected
                    ? Text(
                        formatPln(widget.value).split(',').first,
                        style: T.caption.copyWith(color: base, fontWeight: FontWeight.w700, fontFamily: AppFonts.jetBrainsMono),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: _target),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    builder: (context, f, _) => FractionallySizedBox(
                      heightFactor: f <= 0 ? 0.015 : f,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [topColor, bottomColor],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: T.caption.copyWith(color: selected ? Colors.white : AppColors.mutedText, fontWeight: FontWeight.w500, fontFamily: AppFonts.jetBrainsMono),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedAvgPainter extends CustomPainter {
  const _DashedAvgPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * (1.0 - fraction.clamp(0.0, 1.0));
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    const dash = 5.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, size.width), y),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedAvgPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
}

class _HourlyOverlayPainter extends CustomPainter {
  const _HourlyOverlayPainter({
    required this.rates,
    required this.maxRate,
    required this.color,
  });

  final List<double> rates;
  final double maxRate;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (rates.isEmpty || maxRate <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final n = rates.length;
    final slot = size.width / n;
    for (var i = 0; i < n; i++) {
      final x = slot * (i + 0.5);
      final y = size.height * (1.0 - (rates[i] / maxRate).clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
    final dot = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final x = slot * (i + 0.5);
      final y = size.height * (1.0 - (rates[i] / maxRate).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), 2.2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyOverlayPainter old) =>
      old.maxRate != maxRate ||
      old.color != color ||
      old.rates.length != rates.length;
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.mode, required this.onChanged});

  final _ViewMode mode;
  final ValueChanged<_ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _segment(S.viewWeekly, _ViewMode.weekly),
          _segment(S.viewMonthly, _ViewMode.monthly),
          _segment(S.viewYearly, _ViewMode.yearly),
        ],
      ),
    );
  }

  Widget _segment(String label, _ViewMode value) {
    final selected = mode == value;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: selected
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onChanged(value);
                },
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: _kMinTouchTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? _emerald : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: _emerald.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            style: T.bodyStrong.copyWith(
              color: selected ? Colors.white : AppColors.labelText,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, softWrap: false),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// One bar in the aggregate (monthly / yearly) chart.
class _BarDatum {
  const _BarDatum({
    required this.value,
    required this.heightFactor,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  final double value;
  final double heightFactor;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
}

class _AggregateChart extends StatelessWidget {
  const _AggregateChart({required this.title, required this.bars});

  final String title;
  final List<_BarDatum> bars;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.body.copyWith(color: AppColors.labelText, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < bars.length; i++)
                  Expanded(
                    child: _ChartBar(
                      index: i,
                      value: bars[i].value,
                      heightFactor: bars[i].heightFactor,
                      color: bars[i].color,
                      label: bars[i].label,
                      selected: bars[i].selected,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        bars[i].onTap();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.totalNetProfit,
    required this.avgHourlyRate,
    required this.totalOnlineHours,
    required this.weekCount,
  });

  final String title;
  final double totalNetProfit;
  final double avgHourlyRate;
  final double totalOnlineHours;
  final int weekCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: T.titleXs.copyWith(fontWeight: FontWeight.w900, letterSpacing: 0.3),
          ),
          const SizedBox(height: 4),
          Text(
            S.totalNetProfit,
            style: T.body.copyWith(color: AppColors.labelText, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _CountUp(
                  value: totalNetProfit,
                  style: T.heroMedium.copyWith(color: totalNetProfit >= 0 ? _emerald : _crimson),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'PLN',
                    style: T.titleSm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: (totalNetProfit >= 0 ? _emerald : _crimson)
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _stat(
                '${formatPln(avgHourlyRate)} ${S.perHour}',
                S.avgHourlyRate,
              ),
              _stat(formatHoursHm(totalOnlineHours), S.totalOnlineHours),
              _stat('$weekCount', S.weekCountStat),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: T.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: T.micro.copyWith(color: AppColors.labelText),
          ),
        ],
      ),
    );
  }
}

/// Single "best week" card: the week with the highest hourly rate within the
/// currently viewed period ([weeks]). Shows the week's date range plus its net
/// profit and hourly rate side by side.
class _RecordsCard extends StatefulWidget {
  const _RecordsCard({
    required this.weeks,
    this.celebrateId,
    this.onCelebrateDone,
  });

  final List<WeekEarning> weeks;
  final String? celebrateId;
  final VoidCallback? onCelebrateDone;

  @override
  State<_RecordsCard> createState() => _RecordsCardState();
}

class _RecordsCardState extends State<_RecordsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _stamp;

  @override
  void initState() {
    super.initState();
    _stamp = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _maybeCelebrate();
  }

  @override
  void didUpdateWidget(covariant _RecordsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.celebrateId != widget.celebrateId) _maybeCelebrate();
  }

  void _maybeCelebrate() {
    final id = widget.celebrateId;
    if (id == null) return;
    final best = bestHourlyRateWeek(widget.weeks);
    if (best == null || best.id != id) return;
    _stamp.forward(from: 0).whenComplete(() {
      widget.onCelebrateDone?.call();
    });
  }

  @override
  void dispose() {
    _stamp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final best = bestHourlyRateWeek(widget.weeks);
    final celebrating = widget.celebrateId != null &&
        best != null &&
        best.id == widget.celebrateId;

    return AnimatedBuilder(
      animation: _stamp,
      builder: (context, child) {
        final t = celebrating ? Curves.easeOutBack.transform(_stamp.value) : 1.0;
        final scale = celebrating ? (1.15 - 0.15 * t.clamp(0.0, 1.0)) : 1.0;
        final angle = celebrating ? (0.04 * (1 - t)) : 0.0;
        return Transform.rotate(
          angle: angle,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
        boxShadow: best != null
            ? [
                BoxShadow(
                  color: _gold.withValues(alpha: celebrating ? 0.35 : 0.14),
                  blurRadius: celebrating ? 28 : 20,
                  spreadRadius: celebrating ? 2 : -6,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                size: 18,
                color: _gold,
              ),
              const SizedBox(width: 8),
              Text(
                S.bestWeek,
                style: T.caption.copyWith(color: _gold, fontWeight: FontWeight.w800, letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (best == null)
            Text(
              S.bestWeekEmpty,
              style: T.label,
            )
          else ...[
            Text(
              _weekRangeLabel(best.weekStart, best.weekEnd),
              style: T.titleXs,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _stat(
                  '${formatPln(best.netProfit)} PLN',
                  S.netProfit,
                  best.netProfit >= 0 ? _emerald : _crimson,
                ),
                _stat(
                  '${formatPln(best.hourlyRate)} ${S.perHour}',
                  S.hourlyRate,
                  _hourlyColor(best.hourlyRate),
                ),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.titleLg.copyWith(color: color, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: T.micro.copyWith(color: AppColors.labelText, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({required this.summary, required this.onTap});

  final MonthSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _hourlyColor(summary.avgHourlyRate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _cardColor,
        borderRadius: _cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: _cardRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.hairlineFaint, width: 1),
              borderRadius: _cardRadius,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _monthTitle(summary.month),
                        style: T.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatPln(summary.totalNetProfit)} PLN · ${S.weekCountLabel(summary.weekCount)}',
                        style: T.captionSm,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatPln(summary.avgHourlyRate),
                      style: T.displaySmall.copyWith(
                        color: color,
                        height: 1,
                      ),
                    ),
                    Text(
                      S.perHour,
                      style: T.nano.copyWith(color: color.withValues(alpha: 0.6), fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyWeekCard extends StatelessWidget {
  const _EmptyWeekCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _emerald.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.savings_rounded, size: 30, color: _emerald),
          ),
          const SizedBox(height: 16),
          Text(
            S.noEarnings,
            textAlign: TextAlign.center,
            style: T.body.copyWith(color: AppColors.mutedText, height: 1.4),
          ),
          const SizedBox(height: 18),
          _ActionButton(
            label: S.addWeek,
            icon: Icons.add_rounded,
            filled: true,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

/// Card-shaped empty placeholder used where a list or chart would otherwise
/// leave a blank gap.
class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: AppEmptyState(
        compact: true,
        icon: icon,
        title: title,
        description: description,
      ),
    );
  }
}

/// Stands in for the weekly trend chart until at least two weeks exist.
class _TrendPlaceholder extends StatelessWidget {
  const _TrendPlaceholder();

  @override
  Widget build(BuildContext context) {
    return _EmptyPanel(
      icon: Icons.show_chart_rounded,
      title: S.trendTitle,
      description: S.trendNoData,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? _emerald : _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: _cardRadius,
        side: filled
            ? BorderSide.none
            : const BorderSide(color: _emerald, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        splashColor: (filled ? Colors.white : _emerald).withValues(alpha: 0.25),
        highlightColor: (filled ? Colors.white : _emerald).withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: filled ? Colors.white : _emerald),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.bodyStrong.copyWith(color: filled ? Colors.white : _emerald, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconOnlyButton extends StatelessWidget {
  const _IconOnlyButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: _cardRadius,
        side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        splashColor: color.withValues(alpha: 0.25),
        highlightColor: color.withValues(alpha: 0.12),
        child: SizedBox(
          width: 54,
          height: 54,
          child: Center(child: Icon(icon, color: color, size: 24)),
        ),
      ),
    );
  }
}

/// Bounded, lazily built receipt rows. A shrink-wrapped [ListView] inside a
/// parent [Column]/[ListView] would still construct every child; a height cap
/// gives the builder a real viewport so off-screen tiles stay unbuilt.
class _LazyReceiptList extends StatelessWidget {
  const _LazyReceiptList({
    required this.itemCount,
    required this.estimatedItemExtent,
    required this.itemBuilder,
    this.separatorBuilder,
  });

  final int itemCount;
  final double estimatedItemExtent;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;

  static const double _maxHeight = 280;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0) return const SizedBox.shrink();
    final height = math.min(itemCount * estimatedItemExtent, _maxHeight);
    return SizedBox(
      height: height,
      child: separatorBuilder == null
          ? ListView.builder(
              padding: EdgeInsets.zero,
              primary: false,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            )
          : ListView.separated(
              padding: EdgeInsets.zero,
              primary: false,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
              separatorBuilder: separatorBuilder!,
            ),
    );
  }
}

class _BreakdownCard extends StatefulWidget {
  const _BreakdownCard({
    required this.entry,
    this.breakEven,
    this.onDeleteReceipt,
  });

  final WeekEarning entry;
  final double? breakEven;
  final ValueChanged<String>? onDeleteReceipt;

  @override
  State<_BreakdownCard> createState() => _BreakdownCardState();
}

class _BreakdownCardState extends State<_BreakdownCard> {
  bool _expanded = false;

  WeekEarning get entry => widget.entry;

  @override
  Widget build(BuildContext context) {
    final sun = Theme.of(context).brightness == Brightness.light;
    final threshold = widget.breakEven;
    final belowBreakEven = threshold != null && entry.netIncome < threshold;
    final deductions = entry.rentalFee +
        entry.fuelAfterDiscount +
        entry.vat +
        entry.settlementFee;
    final segments = [
      LoadSegment(
        label: S.rental,
        value: entry.rentalFee,
        color: AppColors.amberFor(sun),
      ),
      LoadSegment(
        label: S.fuelDiscounted,
        value: entry.fuelAfterDiscount,
        color: AppColors.mutedFor(sun),
      ),
      LoadSegment(
        label: S.vat,
        value: entry.vat,
        color: AppColors.mutedFor(sun),
      ),
      LoadSegment(
        label: S.settlementFee,
        value: entry.settlementFee,
        color: AppColors.labelFor(sun),
      ),
      LoadSegment(
        label: S.takeHome,
        value: entry.netProfit.clamp(0, double.infinity),
        color: entry.netProfit < 0
            ? AppColors.crimsonFor(sun)
            : AppColors.emeraldFor(sun),
      ),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: instrumentBezel(sun: sun),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.breakdown,
            style: T.micro.copyWith(color: AppColors.labelFor(sun), fontWeight: FontWeight.w700, letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          _line(S.netIncome, entry.netIncome, income: true, bold: true, sun: sun),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              children: [
                _line(
                  S.rental,
                  -entry.rentalFee,
                  color: AppColors.mutedFor(sun),
                  sun: sun,
                ),
                if (entry.driverMode == DriverMode.paired)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      S.pairedCarTotalSubtitle(
                        formatPln(entry.totalCarRentalFee),
                      ),
                      style: T.caption.copyWith(color: AppColors.labelFor(sun)),
                    ),
                  ),
                if (entry.fuelReceipts.isNotEmpty)
                  _buildFuelReceiptsBreakdown()
                else if (entry.fuelAfterDiscount > 0)
                  _line(
                    S.fuelDiscounted,
                    -entry.fuelAfterDiscount,
                    color: AppColors.mutedFor(sun),
                    sun: sun,
                  ),
                _line(
                  S.vat,
                  -entry.vat,
                  color: AppColors.mutedFor(sun),
                  sun: sun,
                ),
                _line(
                  S.settlementFee,
                  -entry.settlementFee,
                  color: AppColors.mutedFor(sun),
                  sun: sun,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: AppColors.inset,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairlineFaint),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  S.netProfit,
                  style: T.caption.copyWith(color: AppColors.labelFor(sun), fontWeight: FontWeight.w700, letterSpacing: 1.2),
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatPln(entry.netProfit)} PLN',
                  style: T.priceLg.copyWith(
                    color: entry.netProfit >= 0
                        ? AppColors.emeraldFor(sun)
                        : AppColors.crimsonFor(sun),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _iconLine(
            icon: Icons.account_balance_rounded,
            label: S.bankDeposit,
            value: entry.bankDeposit,
            color: entry.bankDeposit >= 0
                ? AppColors.emeraldFor(sun)
                : AppColors.crimsonFor(sun),
            sun: sun,
          ),
          _iconLine(
            icon: Icons.payments_rounded,
            label: S.cashInHand,
            value: entry.cashInHand,
            color: AppColors.amberFor(sun),
            sun: sun,
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !_expanded);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${S.deductions}  −${formatPln(deductions)} PLN',
                          style: T.body.copyWith(color: AppColors.ink(sun), fontWeight: FontWeight.w700),
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: AppColors.labelFor(sun),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LoadMeter(segments: segments, sun: sun),
                  const SizedBox(height: 8),
                  LoadMeterLegend(segments: segments, sun: sun),
                  const SizedBox(height: 8),
                  Text(
                    belowBreakEven ? S.belowBreakEven : S.aboveBreakEven,
                    style: T.labelStrong.copyWith(color: belowBreakEven
                          ? AppColors.amberFor(sun)
                          : AppColors.emeraldFor(sun)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFuelReceiptsBreakdown() {
    final sun = Theme.of(context).brightness == Brightness.light;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.base,
        border: Border.all(color: AppColors.hairlineFaint),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.fuelReceiptsTitle,
            style: T.caption.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _LazyReceiptList(
            itemCount: entry.fuelReceipts.length,
            estimatedItemExtent: 48,
            itemBuilder: (context, i) {
              final receipt = entry.fuelReceipts[i];
              return Dismissible(
                key: ValueKey(receipt.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 8),
                  color: _crimson.withValues(alpha: 0.2),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: _crimson,
                    size: 18,
                  ),
                ),
                onDismissed: (_) {
                  widget.onDeleteReceipt?.call(receipt.id);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '  ${i + 1}. ',
                        style: T.labelStrong.copyWith(color: _amber),
                      ),
                      Expanded(
                        child: Text(
                          '${S.formatReceiptTimestamp(receipt.timestamp)} â€” ${formatPln(receipt.amountPaid)} PLN',
                          style: T.label.copyWith(color: Colors.white),
                        ),
                      ),
                      if (widget.onDeleteReceipt != null)
                        AppTapTarget(
                          onTap: () => widget.onDeleteReceipt?.call(receipt.id),
                          tooltip: S.delete,
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.mutedText,
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(color: AppColors.hairlineStrong, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  S.totalPumpPaid,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${formatPln(entry.fuelPumpPaidTotal)} PLN',
                maxLines: 1,
                style: T.caption.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  S.totalFuelDiscounted,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '-${formatPln(entry.fuelAfterDiscount)} PLN',
                maxLines: 1,
                style: T.caption.copyWith(
                  color: AppColors.mutedFor(sun),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // divider removed — ledger banding uses spacing instead.

  Widget _iconLine({
    required IconData icon,
    required String label,
    required double value,
    required Color color,
    required bool sun,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: sun ? AppColors.ink(sun) : Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: T.body.copyWith(color: AppColors.mutedFor(sun), fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${formatPln(value)} PLN',
            style: T.body.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _line(
    String label,
    double value, {
    bool income = false,
    bool bold = false,
    bool showSign = true,
    Color? color,
    bool sun = false,
  }) {
    final resolved = color ??
        (income ? AppColors.emeraldFor(sun) : AppColors.mutedFor(sun));
    final prefix = showSign
        ? (value < 0 ? '−' : (value > 0 ? '+' : ''))
        : '';
    final absLabel = showSign && value < 0
        ? formatPln(value.abs())
        : formatPln(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: T.bodyStrong.copyWith(color: bold ? AppColors.ink(sun) : AppColors.mutedFor(sun), fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$prefix$absLabel PLN',
            textAlign: TextAlign.right,
            style: T.body.copyWith(color: bold
                  ? (income
                      ? AppColors.emeraldFor(sun)
                      : (value < 0
                          ? AppColors.crimsonFor(sun)
                          : AppColors.ink(sun)))
                  : resolved, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.rangeLabel,
    required this.selected,
    required this.onTap,
  });

  final WeekEarning entry;
  final String rangeLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _hourlyColor(entry.hourlyRate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _cardColor,
        borderRadius: _cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: _cardRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? _emerald : AppColors.hairlineFaint,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: _cardRadius,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rangeLabel,
                        style: T.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatPln(entry.netProfit)} PLN · ${entry.driverTripCount} ${S.tripCount}',
                        style: T.captionSm,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatPln(entry.hourlyRate),
                      style: T.displaySmall.copyWith(
                        color: color,
                        height: 1,
                      ),
                    ),
                    Text(
                      S.perHour,
                      style: T.nano.copyWith(color: color.withValues(alpha: 0.6), fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EarningsFormScreen extends StatefulWidget {
  const _EarningsFormScreen({
    required this.existing,
    required this.weekStart,
    required this.weekEnd,
  });

  final WeekEarning? existing;
  final DateTime weekStart;
  final DateTime weekEnd;

  @override
  State<_EarningsFormScreen> createState() => _EarningsFormScreenState();
}

class _EarningsFormScreenState extends State<_EarningsFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _netIncomeCtrl;
  late final TextEditingController _cashCtrl;
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _minutesCtrl;
  late final TextEditingController _driverTripsCtrl;
  late final TextEditingController _carTripsOverrideCtrl;
  late bool _hasRentalDiscount;
  late final ValueNotifier<List<FuelReceipt>> _fuelReceiptsNotifier;
  List<FuelReceipt> get _fuelReceipts => _fuelReceiptsNotifier.value;
  DriverMode get _formDriverMode =>
      widget.existing?.driverMode ?? activeDriverMode;

  double get _fuelPumpTotal =>
      _fuelReceipts.fold(0.0, (sum, r) => sum + r.amountPaid);

  /// Set after a failed save when online time (hours + minutes) is missing;
  /// drives the inline "eksik veri" indicator under the online-time row.
  bool _onlineTimeMissing = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _netIncomeCtrl = TextEditingController(
      text: e != null ? _num(e.netIncome) : '',
    );
    _cashCtrl = TextEditingController(
      text: e != null ? _num(e.cashReceived) : '',
    );
    final hours = e?.onlineHours ?? 0;
    _hoursCtrl = TextEditingController(
      text: e != null ? '${hours.truncate()}' : '',
    );
    _minutesCtrl = TextEditingController(
      text: e != null ? '${((hours - hours.truncate()) * 60).round()}' : '',
    );
    _driverTripsCtrl = TextEditingController(
      text: e != null ? '${e.driverTripCount}' : '',
    );
    _carTripsOverrideCtrl = TextEditingController(
      text: (e != null && e.carTripCountOverride != null)
          ? '${e.carTripCountOverride}'
          : '',
    );
    _hasRentalDiscount = e?.hasRentalDiscount ?? true;
    final initialReceipts =
        capFuelReceipts(List<FuelReceipt>.from(e?.fuelReceipts ?? []));
    if (initialReceipts.isEmpty && e != null && e.fuelPumpPaidTotal > 0) {
      initialReceipts.add(
        FuelReceipt(timestamp: e.weekStart, amountPaid: e.fuelPumpPaidTotal),
      );
    }
    _fuelReceiptsNotifier = ValueNotifier<List<FuelReceipt>>(initialReceipts);

    // One merged listenable drives ONLY the preview widgets below;
    // typing no longer rebuilds the entire form.
    _previewListenable = Listenable.merge([
      _netIncomeCtrl,
      _hoursCtrl,
      _minutesCtrl,
      _driverTripsCtrl,
      _carTripsOverrideCtrl,
      _cashCtrl,
      _fuelReceiptsNotifier,
    ]);
    // Keep a single targeted listener for the error-flag state change.
    _hoursCtrl.addListener(_maybeClearTimeError);
    _minutesCtrl.addListener(_maybeClearTimeError);
  }

  late final Listenable _previewListenable;

  void _maybeClearTimeError() {
    if (_onlineTimeMissing &&
        onlineHoursFromHm(_parseInt(_hoursCtrl), _parseInt(_minutesCtrl)) > 0) {
      setState(
        () => _onlineTimeMissing = false,
      ); // rare, user-visible change only
    }
  }

  String _num(double v) => formatPln(v);

  /// Parses a money/decimal field, clamping negatives to 0. The input
  /// formatters already block a typed minus sign; this is a defensive backstop
  /// so a negative can never reach the calculations.
  double _parse(TextEditingController c) {
    final t = c.text
        .trim()
        .replaceAll('\u00A0', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    if (t.isEmpty) return 0;
    final v = double.tryParse(t) ?? 0;
    return v < 0 ? 0 : v;
  }

  /// Parses an integer field, clamping negatives to 0 (e.g. trip count).
  int _parseInt(TextEditingController c) {
    final v = int.tryParse(c.text.trim()) ?? 0;
    return v < 0 ? 0 : v;
  }

  @override
  void dispose() {
    _hoursCtrl.removeListener(_maybeClearTimeError);
    _minutesCtrl.removeListener(_maybeClearTimeError);
    _netIncomeCtrl.dispose();
    _cashCtrl.dispose();
    _hoursCtrl.dispose();
    _minutesCtrl.dispose();
    _driverTripsCtrl.dispose();
    _carTripsOverrideCtrl.dispose();
    _fuelReceiptsNotifier.dispose();
    super.dispose();
  }

  bool _saved = false;

  int get _currentDriverTrips => _parseInt(_driverTripsCtrl);

  int? get _currentCarTripOverride =>
      _formDriverMode == DriverMode.paired &&
              _carTripsOverrideCtrl.text.trim().isNotEmpty
          ? _parseInt(_carTripsOverrideCtrl)
          : null;

  int get _currentCarTrips => _formDriverMode == DriverMode.paired
      ? (_currentCarTripOverride ?? _currentDriverTrips)
      : _currentDriverTrips;

  void _save() {
    // Re-entrancy guard: a second tap during the pop transition would
    // otherwise pop the EarningsScreen underneath this route.
    if (_saved || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final hours = onlineHoursFromHm(
      _parseInt(_hoursCtrl),
      _parseInt(_minutesCtrl),
    );
    // Guard the fields where 0 is never a real-world value: an incomplete
    // entry saved with netIncome/trips/hours == 0 would compute a plausible-
    // looking (but wrong) negative result instead of surfacing the mistake.
    final formOk = _formKey.currentState?.validate() ?? false;
    final timeOk = hours > 0;
    if (!formOk || !timeOk) {
      setState(() => _onlineTimeMissing = !timeOk);
      HapticFeedback.heavyImpact();
      return;
    }
    _saved = true;
    final existing = widget.existing;
    final entry = WeekEarning(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      weekStart: widget.weekStart,
      weekEnd: widget.weekEnd,
      driverMode: _formDriverMode,
      netIncome: _parse(_netIncomeCtrl),
      cashReceived: _parse(_cashCtrl),
      onlineHours: hours,
      driverTripCount: _currentDriverTrips,
      carTripCountOverride: _currentCarTripOverride,
      hasRentalDiscount: _hasRentalDiscount,
      fuelReceipts: _fuelReceipts,
    );
    Navigator.of(context).pop(entry);
  }

  /// Rental tier bracket for the currently entered car trip count and mode.
  RentalTier _rentalTier() =>
      expectedRentalTier(_currentCarTrips, _formDriverMode);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      appBar: AppBar(
        backgroundColor: AppColors.scaffold(
          Theme.of(context).brightness == Brightness.light,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.existing == null ? S.addWeek : S.editWeek,
          style: T.titleMd,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              _lockedWeekBanner(),
              const SizedBox(height: 20),
              _numField(
                _netIncomeCtrl,
                S.netIncome,
                suffix: 'PLN',
                required: true,
                positive: true,
                helper: S.netIncomeHint,
              ),
              ListenableBuilder(
                listenable: _previewListenable,
                builder: (context, _) => _breakEvenReference(),
              ),
              _numField(
                _driverTripsCtrl,
                S.driverTripCountLabel,
                integer: true,
                required: true,
                positive: true,
              ),
              if (_formDriverMode == DriverMode.paired)
                _numField(
                  _carTripsOverrideCtrl,
                  S.carTripCountOverrideLabel,
                  integer: true,
                  required: false,
                  positive: false,
                  helper: S.carTripCountOverrideHint,
                ),
              _rentalDiscountToggleRow(),
              ListenableBuilder(
                listenable: _previewListenable,
                builder: (context, _) => _computedRentalDisplay(),
              ),
              const SizedBox(height: 12),
              _buildFuelReceiptsSection(),
              _numField(_cashCtrl, S.cashReceived, suffix: 'PLN'),
              _label(S.onlineTime),
              _DurationField(
                totalMinutes:
                    _parseInt(_hoursCtrl) * 60 + _parseInt(_minutesCtrl),
                onChanged: (mins) {
                  final clamped = mins.clamp(0, 999 * 60);
                  _hoursCtrl.text = '${clamped ~/ 60}';
                  _minutesCtrl.text = '${clamped % 60}';
                  _maybeClearTimeError();
                  setState(() {});
                },
              ),
              if (_onlineTimeMissing) _inlineError(S.onlineTimeMissing),
              ListenableBuilder(
                listenable: _previewListenable,
                builder: (context, _) {
                  final preview = WeekEarning(
                    id: 'preview',
                    weekStart: widget.weekStart,
                    weekEnd: widget.weekEnd,
                    driverMode: _formDriverMode,
                    netIncome: _parse(_netIncomeCtrl),
                    cashReceived: _parse(_cashCtrl),
                    onlineHours: onlineHoursFromHm(
                      _parseInt(_hoursCtrl),
                      _parseInt(_minutesCtrl),
                    ),
                    driverTripCount: _currentDriverTrips,
                    carTripCountOverride: _currentCarTripOverride,
                    hasRentalDiscount: _hasRentalDiscount,
                    fuelReceipts: _fuelReceipts,
                  );
                  final warnings = preview.warnings;
                  if (warnings.isEmpty) return const SizedBox.shrink();
                  return Column(
                    children: [
                      const SizedBox(height: 4),
                      _WarningList(warnings: warnings),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              _ActionButton(
                label: S.save,
                icon: Icons.check_rounded,
                filled: true,
                onTap: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lockedWeekBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_rounded,
            size: 16,
            color: AppColors.labelText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _weekRangeLabel(widget.weekStart, widget.weekEnd),
              style: T.titleXs,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
    child: Text(
      text,
      style: T.caption.copyWith(color: AppColors.labelText, fontWeight: FontWeight.w800, letterSpacing: 1.5),
    ),
  );

  Future<void> _addReceiptInline() async {
    final ctrl = TextEditingController();
    double? added;
    try {
      added = await showDialog<double>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.mdRadius,
            ),
            title: Text(
              S.quickAddFuelTitle,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: T.titleLg,
              autofocus: true,
              decoration: InputDecoration(
                labelText: S.amountPaidLabel,
                labelStyle: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: AppColors.mutedText,
                ),
                suffixText: 'PLN',
                suffixStyle: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: _amber,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.hairlineStrong),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: _amber),
                ),
              ),
              onSubmitted: (_) {
                final val = double.tryParse(
                  ctrl.text.replaceAll(',', '.').trim(),
                );
                if (val != null && val > 0) {
                  Navigator.of(ctx).pop(val);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  S.cancel,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: AppColors.mutedText,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _amber,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final val = double.tryParse(
                    ctrl.text.replaceAll(',', '.').trim(),
                  );
                  if (val != null && val > 0) {
                    Navigator.of(ctx).pop(val);
                  }
                },
                child: Text(
                  S.add,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }

    if (added == null || added <= 0 || !mounted) return;
    _fuelReceiptsNotifier.value = capFuelReceipts([
      ..._fuelReceiptsNotifier.value,
      FuelReceipt(timestamp: DateTime.now(), amountPaid: added),
    ]);
  }

  Widget _buildFuelReceiptsSection() {
    return ValueListenableBuilder<List<FuelReceipt>>(
      valueListenable: _fuelReceiptsNotifier,
      builder: (context, receipts, _) {
        final totalPaid = receipts.fold(0.0, (sum, r) => sum + r.amountPaid);
        final discounted = computeFuelAfterDiscount(totalPaid);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _label(S.fuelReceiptsTitle)),
                const SizedBox(width: 8),
                Flexible(
                  child: TextButton.icon(
                    onPressed: _addReceiptInline,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, _kMinTouchTarget),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18, color: _amber),
                    label: Text(
                      S.addReceipt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.labelStrong.copyWith(color: _amber),
                    ),
                  ),
                ),
              ],
            ),
            if (receipts.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.base,
                  border: Border.all(color: AppColors.hairlineFaint),
                  borderRadius: AppRadius.mdRadius,
                ),
                child: AppEmptyState(
                  compact: true,
                  accent: _amber,
                  icon: Icons.local_gas_station_rounded,
                  title: S.fuelReceiptsTitle,
                  description: S.noFuelReceipts,
                  actionLabel: S.addReceipt,
                  onAction: _addReceiptInline,
                ),
              )
            else ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.base,
                  border: Border.all(color: AppColors.hairlineFaint),
                  borderRadius: AppRadius.mdRadius,
                ),
                child: Column(
                  children: [
                    _LazyReceiptList(
                      itemCount: receipts.length,
                      estimatedItemExtent: 72,
                      separatorBuilder: (_, _) =>
                          const Divider(color: AppColors.hairlineFaint, height: 1),
                      itemBuilder: (context, i) {
                        final item = receipts[i];
                        return Dismissible(
                          key: ValueKey(item.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            color: _crimson.withValues(alpha: 0.2),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: _crimson,
                            ),
                          ),
                          onDismissed: (_) {
                            final removed = item;
                            final idx = i;
                            _fuelReceiptsNotifier.value =
                                _fuelReceiptsNotifier.value
                                    .where((r) => r.id != item.id)
                                    .toList();
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 4),
                                content: Text(S.receiptDeleted),
                                action: SnackBarAction(
                                  label: S.undo,
                                  onPressed: () {
                                    final next = [
                                      ..._fuelReceiptsNotifier.value,
                                    ];
                                    final insertAt =
                                        idx.clamp(0, next.length);
                                    next.insert(insertAt, removed);
                                    _fuelReceiptsNotifier.value =
                                        capFuelReceipts(next);
                                  },
                                ),
                              ),
                            );
                          },
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                            leading: CircleAvatar(
                              radius: 13,
                              backgroundColor: _amber.withValues(alpha: 0.15),
                              child: Text(
                                '${i + 1}',
                                style: T.caption.copyWith(color: _amber, fontWeight: FontWeight.w800),
                              ),
                            ),
                            title: Text(
                              '${formatPln(item.amountPaid)} PLN',
                              style: T.titleXs.copyWith(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              S.formatReceiptTimestamp(item.timestamp),
                              style: T.caption,
                            ),
                            trailing: IconButton(
                              tooltip: S.delete,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.mutedText,
                                size: 20,
                              ),
                              onPressed: () {
                                _fuelReceiptsNotifier.value =
                                    _fuelReceiptsNotifier.value
                                        .where((r) => r.id != item.id)
                                        .toList();
                              },
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(color: AppColors.hairlineStrong, height: 1),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  S.totalPumpPaid,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.label,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${formatPln(totalPaid)} PLN',
                                maxLines: 1,
                                style: T.body.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  S.totalFuelDiscounted,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.label.copyWith(color: _emerald),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${formatPln(discounted)} PLN',
                                maxLines: 1,
                                style: T.titleXs.copyWith(color: _emerald),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Current live rental fee for the entered trips and rates (mirrors
  /// [WeekEarning.rentalFee]).
  double _currentRentalFee() => _rentalTier().fee;

  /// Real, post-discount fuel cost for the amount currently typed in the pump
  /// field. Empty/unparsed input reads as 0 (matching the other live previews),
  /// so the break-even simply reflects the fixed costs so far and rises the
  /// instant fuel is entered.
  double _currentFuelAfterDiscount() =>
      computeFuelAfterDiscount(_fuelPumpTotal);

  /// Subtle, live break-even reference under the Net Gelir field. Reads the LIVE
  /// pump-paid field (Ã— 0.90 discount) plus the rental toggle / trip count, so
  /// the driver sees â€” updated on every keystroke â€” the turnover they have to
  /// clear this week before the week pays for itself.
  Widget _breakEvenReference() {
    final threshold = calculateBreakEven(
      fixedCosts: _currentFuelAfterDiscount() + _currentRentalFee(),
    );
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, size: 15, color: _amber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              S.breakEvenLabel(formatPln(threshold)),
              style: T.caption.copyWith(color: _amber, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rentalDiscountToggleRow() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: _emerald,
          title: Text(
            S.hasRentalDiscountToggle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.body.copyWith(fontWeight: FontWeight.w700),
          ),
          value: _hasRentalDiscount,
          onChanged: (val) {
            setState(() => _hasRentalDiscount = val);
          },
        ),
      ),
    );
  }

  /// Read-only, formula-driven rental fee. Recomputes live from trip count
  /// and rental discount toggle.
  Widget _computedRentalDisplay() {
    final tier = _rentalTier();
    final noDiscountFee = _formDriverMode == DriverMode.paired ? 450.0 : 900.0;
    final label = _hasRentalDiscount
        ? S.rentalComputed(rentalTierRangeLabel(tier), formatPln(tier.fee))
        : S.rentalNoDiscount(formatPln(noDiscountFee));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _emerald.withValues(alpha: 0.08),
        border: Border.all(color: _emerald.withValues(alpha: 0.4), width: 1),
        borderRadius: _cardRadius,
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_rounded, size: 18, color: _emerald),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: T.bodyStrong,
            ),
          ),
        ],
      ),
    );
  }

  /// Inline red "eksik veri" style message, used where a Form validator can't
  /// attach directly (the split hours/minutes online-time row).
  Widget _inlineError(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 12),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, size: 15, color: _crimson),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: T.caption.copyWith(color: _crimson, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  /// Shared validator for required / must-be-positive numeric fields. A blank
  /// entry fails as "zorunlu"; a 0 (or unparseable) entry on a positive field
  /// fails as "eksik veri" so silent-zero data can't be saved.
  String? _validateField(
    String? v, {
    required bool required,
    required bool positive,
    double maxVal = 999999.0,
  }) {
    final t = (v ?? '')
        .trim()
        .replaceAll('\u00A0', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    if (t.isEmpty) return (required || positive) ? S.requiredField : null;
    final parsed = double.tryParse(t);
    if (positive) {
      if (parsed == null || parsed <= 0) return S.enterValidAmount;
    } else if (required) {
      if (parsed == null || parsed < 0) return S.enterValidAmount;
    }
    if (parsed != null && parsed > maxVal) {
      return S.enterValidAmount;
    }
    return null;
  }

  Widget _numField(
    TextEditingController controller,
    String label, {
    String? suffix,
    bool integer = false,
    bool required = false,
    bool positive = false,
    bool dense = false,
    String? helper,
    double maxVal = 999999.0,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: integer
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: integer
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(7),
              ]
            : [
                _PlnInputFormatter(),
                LengthLimitingTextInputFormatter(12),
              ],
        style: T.titleSm.copyWith(fontWeight: FontWeight.w700, fontFamily: integer ? AppFonts.dmSans : AppFonts.jetBrainsMono),
        validator: (v) => _validateField(
          v,
          required: required,
          positive: positive,
          maxVal: maxVal,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: T.body.copyWith(color: AppColors.mutedText),
          helperText: helper,
          helperMaxLines: 3,
          helperStyle: T.captionSm.copyWith(color: AppColors.labelText, height: 1.3),
          suffixText: suffix,
          suffixStyle: T.label.copyWith(color: AppColors.labelText, fontFamily: AppFonts.jetBrainsMono),
          filled: true,
          fillColor: _cardColor,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: dense ? 14 : 18,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: _cardRadius,
            borderSide: const BorderSide(color: AppColors.hairlineFaint, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: _cardRadius,
            borderSide: const BorderSide(color: _emerald, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: _cardRadius,
            borderSide: const BorderSide(color: _crimson, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: _cardRadius,
            borderSide: const BorderSide(color: _crimson, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// PDF export date-range choices.
enum _ExportRange { thisMonth, specificMonth, thisYear, allTime }

/// Large tappable row used in the PDF range-selector sheet.
class _RangeOption extends StatelessWidget {
  const _RangeOption({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: _cardRadius,
        side: const BorderSide(color: AppColors.hairlineFaint, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              const Icon(Icons.calendar_month_rounded, size: 20, color: _emerald),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: T.titleSm,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.labelText),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreeWeekProgressCard extends StatefulWidget {
  const _FreeWeekProgressCard({
    required this.lifetimeTrips,
    required this.onReset,
    required this.onEdit,
  });

  final int lifetimeTrips;
  final VoidCallback onReset;
  final VoidCallback onEdit;

  @override
  State<_FreeWeekProgressCard> createState() => _FreeWeekProgressCardState();
}

class _FreeWeekProgressCardState extends State<_FreeWeekProgressCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    _ensurePulse();
  }

  @override
  void didUpdateWidget(covariant _FreeWeekProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensurePulse();
  }

  void _ensurePulse() {
    final progress =
        calculateCurrentFreeWeekProgress(widget.lifetimeTrips);
    final frac = (progress / kFreeWeekTripThreshold).clamp(0.0, 1.0);
    final near = frac >= 0.90 && frac < 1.0;
    if (near && _pulse == null) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2000),
      )..repeat(reverse: true);
    } else if (!near && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        calculateCurrentFreeWeekProgress(widget.lifetimeTrips);
    final earned = calculateFreeWeeksEarned(widget.lifetimeTrips);
    final frac = (progress / kFreeWeekTripThreshold).clamp(0.0, 1.0);
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: frac,
        backgroundColor: AppColors.raised,
        valueColor: const AlwaysStoppedAnimation<Color>(_gold),
        minHeight: 6,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard_rounded, size: 18, color: _gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.freeWeekProgress(progress, kFreeWeekTripThreshold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.bodyStrong,
                ),
              ),
              Odometer(value: widget.lifetimeTrips, digits: 4, digitHeight: 22),
              const SizedBox(width: 4),
              AppTapTarget(
                onTap: widget.onEdit,
                tooltip: S.editLifetimeTripsTitle,
                child: const Icon(Icons.edit_rounded, size: 20, color: _gold),
              ),
              AppTapTarget(
                onTap: widget.onReset,
                tooltip: S.resetLifetimeTripsTitle,
                child: const Icon(Icons.restart_alt_rounded, size: 20, color: _gold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_pulse != null)
            AnimatedBuilder(
              animation: _pulse!,
              builder: (context, child) {
                final glow = 0.35 + 0.45 * _pulse!.value;
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: _gold.withValues(alpha: glow * 0.55),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: bar,
            )
          else
            bar,
          if (earned > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.15),
                border: Border.all(
                  color: _gold.withValues(alpha: 0.5),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.card_giftcard_rounded,
                    size: 16,
                    color: _gold,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      earned > 1
                          ? S.freeWeekRewardBadgeCount(earned)
                          : S.freeWeekRewardBadge,
                      style: T.caption.copyWith(color: _gold, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Single `H:MM` online-time control with ±15 minute steppers.
class _DurationField extends StatelessWidget {
  const _DurationField({
    required this.totalMinutes,
    required this.onChanged,
  });

  final int totalMinutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    final label = '$h:${m.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: _cardRadius,
          border: _cardBorder,
        ),
        child: Row(
          children: [
            AppCircleButton(
              icon: Icons.remove_rounded,
              color: AppColors.crimson,
              mediumHaptic: true,
              onTap: () => onChanged(totalMinutes - 15),
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: T.displayMedium,
              ),
            ),
            AppCircleButton(
              icon: Icons.add_rounded,
              color: AppColors.emerald,
              onTap: () => onChanged(totalMinutes + 15),
            ),
          ],
        ),
      ),
    );
  }
}
