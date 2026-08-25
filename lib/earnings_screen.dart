import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rate_helper/fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_widgets.dart';
import 'earnings_models.dart';
import 'earnings_pdf_export.dart';
import 'l10n.dart';
import 'log.dart';

const kDriverNameKey = 'driver_name';

const _cardColor = AppColors.card;
const _emerald = AppColors.emerald;
const _crimson = AppColors.crimson;
const _amber = AppColors.amber;
final _cardBorder = Border.all(color: AppColors.cardBorderColor, width: 1);
final _cardRadius = BorderRadius.circular(16);

/// PLN/hour above which the hourly rate is considered "good" (green).
const double _goodHourlyThreshold = 30.0;

/// Gold accent used for the record badges.
const _gold = AppColors.gold;

/// Minimum tap area for controls used while driving.
const double _kMinTouchTarget = kMinTouchTarget;

/// Chart / summary granularity selectable from the segmented control.
enum _ViewMode { weekly, monthly, yearly }

/// Max number of weeks shown in the weekly trend chart. Fixed so the chart's
/// width/layout never grows as more history accumulates — older weeks stay
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
        backgroundColor: AppColors.dialog,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          S.driverModeDialogTitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: activeDriverMode == DriverMode.solo
                  ? AppColors.selected
                  : Colors.transparent,
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
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
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
            const SizedBox(height: 8),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: activeDriverMode == DriverMode.paired
                  ? AppColors.selected
                  : Colors.transparent,
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
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
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

/// Localized text for an informational cross-check warning.
String _warningText(EarningsWarning w) {
  switch (w) {
    case EarningsWarning.hourlyRate:
      return S.warnHourlyRate;
  }
}

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key, this.autoAddWeek = false});

  /// When true, the "add new week" form for the current week opens
  /// automatically after the first load.
  final bool autoAddWeek;

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
    // permanently uncounted — the same limitation as before, just frozen.
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
  }

  /// Guards against re-opening the auto-add form on every reload.
  bool _autoAddTriggered = false;

  int _cachedLifetimeTrips = 0;

  List<WeekEarning> _trend = const [];
  List<DateTime> _histMonths = const [];

  /// Replaces the entry list and refreshes the memoized monthly/yearly rollups.
  /// The only place [_entries] should be reassigned, so the caches never drift.
  /// Note: _cachedLifetimeTrips is NOT recomputed here — it is loaded from the
  /// persisted SharedPreferences odometer and updated only on new/edited saves.
  void _setEntries(List<WeekEarning> entries) {
    _entries = entries;
    _rowKeys.removeWhere((id, _) => !entries.any((e) => e.id == id));
    _months = aggregateByMonth(entries);
    _years = aggregateByYear(entries);
    _trend = _computeTrendWeeks(entries);
    _histMonths = _computeHistoryMonths(entries);
  }

  /// Distinct calendar months present in [_entries], oldest → newest.
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
        backgroundColor: AppColors.elevated,
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
          backgroundColor: AppColors.elevated,
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
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: AppColors.mutedText,
                    fontSize: 13,
                    height: 1.4,
                  ),
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

  /// Up to the last [_trendWeekWindow] recorded weeks, ordered oldest → newest
  /// for the chart. [_entries] is kept newest-first, so reverse it to
  /// chronological order first, then keep only the trailing (most recent)
  /// slice — this caps the chart to a fixed window so it never grows wider as
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
    final oldTrips = existing?.tripCount ?? 0;
    final tripDelta = result.tripCount - oldTrips;
    setState(() {
      final next = [..._entries]
        ..removeWhere(
          (e) => e.id == result.id || isSameDate(e.weekStart, result.weekStart),
        )
        ..add(result)
        ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
      _setEntries(next);
    });
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
            backgroundColor: AppColors.elevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: Colors.white,
                fontSize: 18,
              ),
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
                  color: _gold,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: _gold),
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
                  backgroundColor: _gold,
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
        tripCount: 0,
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
        backgroundColor: AppColors.track,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _quickAddFuel,
        backgroundColor: _gold,
        foregroundColor: Colors.black,
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
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          S.earningsTitle,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
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
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
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
  /// the dialog without saving (dismissed prompts never block PDF export —
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
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              color: Colors.white,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              labelText: S.driverNameLabel,
              labelStyle: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: AppColors.mutedText,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.strongBorder),
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

  /// Prompts for a range (Bu Ay / Bu Yıl / Tüm Zamanlar), then builds and
  /// shares a plain PDF earnings report for the weeks in that range.
  Future<void> _exportPdf() async {
    final choice = await showModalBottomSheet<_ExportRange>(
      context: context,
      backgroundColor: AppColors.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              S.exportPdfRangeTitle,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: AppColors.labelText,
              ),
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
        // to-its-weekStart-month rule — no separate ad-hoc filter to drift.
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
      backgroundColor: AppColors.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                S.exportPickMonthTitle,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: AppColors.labelText,
                ),
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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
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
                          color: AppColors.elevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.disabledText),
                        ),
                        child: Text(
                          S.driverModeLabel(
                            activeDriverMode == DriverMode.paired,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.dmSans,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.mutedText,
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
  Widget _recordsSliver(List<WeekEarning> weeks) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: _RecordsCard(weeks: weeks),
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
              // historical average — consistent with the live entry-form
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
      // whole story — an extra "HISTORY / no data" block would just repeat it.
      if (_entries.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              S.history,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: AppColors.labelText,
              ),
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
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Text(
            _monthTitle(selected.month).toUpperCase(),
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: AppColors.labelText,
            ),
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: _kMinTouchTarget),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _emerald.withValues(alpha: 0.12)
              : const Color(0x0AFFFFFF),
          border: Border.all(
            color: selected
                ? _emerald.withValues(alpha: 0.45)
                : AppColors.cardBorderColor,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppFonts.dmSans,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? Colors.white : AppColors.labelText,
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: _kMinTouchTarget,
        child: Row(
          children: [
            Flexible(
              child: Text(
                '${S.driverNameLabel}: ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedText,
                ),
              ),
            ),
            Flexible(
              child: Text(
                display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.mutedText,
                ),
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
          _arrow(Icons.chevron_left_rounded, true, () {
            HapticFeedback.selectionClick();
            onPrev();
          }),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
          _arrow(Icons.chevron_right_rounded, canGoForward, () {
            HapticFeedback.selectionClick();
            onNext?.call();
          }),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 30,
          color: enabled ? Colors.white : const Color(0x26FFFFFF),
        ),
      ),
    );
  }
}

/// Animated count-up for hero numbers. On value change it lerps from the
/// previously shown value to the new one over 400ms, formatting each frame
/// with the app's PLN formatter — the single highest-impact "alive" touch.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});

  final double value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(formatPln(v), style: style),
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
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
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
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.labelText,
            ),
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
                  style: TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    S.perHour,
                    style: TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: color.withValues(alpha: 0.7),
                    ),
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
      textStyle: const TextStyle(
        fontFamily: AppFonts.dmSans,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.35,
      ),
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
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _amber,
                ),
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

  /// Oldest → newest, up to 12 weeks.
  final List<WeekEarning> weeks;
  final DateTime selectedStart;
  final void Function(WeekEarning) onBarTap;

  @override
  Widget build(BuildContext context) {
    final maxRate = weeks.fold<double>(0, (m, w) => math.max(m, w.hourlyRate));
    final safeMax = maxRate > 0 ? maxRate : 1.0;

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
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
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
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.labelText,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  S.fourWeekAverage(formatPln(last4Avg)),
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
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
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < weeks.length; i++)
                  Expanded(
                    child: _ChartBar(
                      index: i,
                      value: weeks[i].hourlyRate,
                      heightFactor: (weeks[i].hourlyRate / safeMax).clamp(
                        0.0,
                        1.0,
                      ),
                      label:
                          '${weeks[i].weekStart.day}.${weeks[i].weekStart.month}',
                      selected: isSameDate(weeks[i].weekStart, selectedStart),
                      onTap: () => onBarTap(weeks[i]),
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

/// Shared bar for both the weekly trend and the aggregate (monthly/yearly)
/// charts. Grows its height in with an [index]-staggered cascade (30ms per bar)
/// and paints a top→bottom green gradient with rounded top corners.
class _ChartBar extends StatefulWidget {
  const _ChartBar({
    required this.index,
    required this.value,
    required this.heightFactor,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final double value;
  final double heightFactor;
  final String label;
  final bool selected;
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
    final topColor = selected ? _emerald : _emerald.withValues(alpha: 0.32);
    final bottomColor = selected
        ? Color.lerp(_emerald, Colors.black, 0.32)!
        : _emerald.withValues(alpha: 0.12);
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              formatPln(widget.value).split(',').first,
              style: TextStyle(
                fontFamily: AppFonts.jetBrainsMono,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: selected ? _emerald : AppColors.labelText,
              ),
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
              style: TextStyle(
                fontFamily: AppFonts.jetBrainsMono,
                fontSize: 8,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white : AppColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      child: GestureDetector(
        onTap: selected
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged(value);
              },
        behavior: HitTestBehavior.opaque,
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
            style: TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
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
  });

  final double value;
  final double heightFactor;
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

class _AggregateChart extends StatelessWidget {
  const _AggregateChart({required this.title, required this.bars});

  final String title;
  final List<_BarDatum> bars;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
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
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.labelText,
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
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
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.totalNetProfit,
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.labelText,
            ),
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
                  style: TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    color: totalNetProfit >= 0 ? _emerald : _crimson,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'PLN',
                    style: TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: 16,
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
            style: const TextStyle(
              fontFamily: AppFonts.jetBrainsMono,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.labelText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Single "best week" card: the week with the highest hourly rate within the
/// currently viewed period ([weeks]). Shows the week's date range plus its net
/// profit and hourly rate side by side.
class _RecordsCard extends StatelessWidget {
  const _RecordsCard({required this.weeks});

  final List<WeekEarning> weeks;

  @override
  Widget build(BuildContext context) {
    final best = bestHourlyRateWeek(weeks);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
        boxShadow: best != null
            ? [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.14),
                  blurRadius: 20,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                S.bestWeek,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: _gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (best == null)
            Text(
              S.bestWeekEmpty,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedText,
              ),
            )
          else ...[
            Text(
              _weekRangeLabel(best.weekStart, best.weekEnd),
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
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
            style: TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.labelText,
            ),
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
              border: Border.all(color: AppColors.cardBorderColor, width: 1),
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
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatPln(summary.totalNetProfit)} PLN · ${S.weekCountLabel(summary.weekCount)}',
                        style: const TextStyle(
                          fontFamily: AppFonts.jetBrainsMono,
                          fontSize: 11,
                          color: AppColors.mutedText,
                        ),
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
                      style: TextStyle(
                        fontFamily: AppFonts.dmSans,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1,
                      ),
                    ),
                    Text(
                      S.perHour,
                      style: TextStyle(
                        fontFamily: AppFonts.dmSans,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color.withValues(alpha: 0.6),
                        letterSpacing: 0.5,
                      ),
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
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
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
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              color: AppColors.mutedText,
              fontSize: 14,
              height: 1.4,
            ),
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: filled ? _emerald : _cardColor,
          border: filled ? null : Border.all(color: _emerald, width: 1.5),
          borderRadius: _cardRadius,
        ),
        alignment: Alignment.center,
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
                style: TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: filled ? Colors.white : _emerald,
                ),
              ),
            ),
          ],
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: _cardColor,
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          borderRadius: _cardRadius,
        ),
        child: Icon(icon, color: color, size: 24),
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

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.entry,
    this.breakEven,
    this.onDeleteReceipt,
  });

  final WeekEarning entry;

  /// Break-even net-income threshold for this week. When [entry.netIncome] is
  /// below it, an informational (non-blocking) amber note is shown.
  final double? breakEven;
  final ValueChanged<String>? onDeleteReceipt;

  @override
  Widget build(BuildContext context) {
    final threshold = breakEven;
    final belowBreakEven = threshold != null && entry.netIncome < threshold;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.breakdown,
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.labelText,
            ),
          ),
          const SizedBox(height: 14),
          _line(S.netIncome, entry.netIncome, income: true, bold: true),
          const SizedBox(height: 6),
          _line(S.rental, -entry.rentalFee),
          if (entry.driverMode == DriverMode.paired)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                S.pairedCarTotalSubtitle(formatPln(entry.totalCarRentalFee)),
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 11,
                  color: AppColors.labelText,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          if (entry.fuelReceipts.isNotEmpty)
            _buildFuelReceiptsBreakdown()
          // A bare "-0,00 PLN" fuel row reads as a bug; drop the line entirely
          // when no fuel was recorded for the week.
          else if (entry.fuelAfterDiscount > 0)
            _line(S.fuelDiscounted, -entry.fuelAfterDiscount),
          _line(S.vat, -entry.vat),
          _line(S.settlementFee, -entry.settlementFee),
          _divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  S.netProfit,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                '${formatPln(entry.netProfit)} PLN',
                style: TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: entry.netProfit >= 0 ? _emerald : _crimson,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _line(
            '🏦 ${S.bankDeposit}',
            entry.bankDeposit,
            color: entry.bankDeposit >= 0 ? _emerald : _crimson,
            showSign: false,
          ),
          _line(
            '💵 ${S.cashInHand}',
            entry.cashInHand,
            color: _amber,
            showSign: false,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  S.hourlyRate,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedText,
                  ),
                ),
              ),
              Text(
                '${formatPln(entry.hourlyRate)} ${S.perHour}',
                style: TextStyle(
                  fontFamily: AppFonts.jetBrainsMono,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _hourlyColor(entry.hourlyRate),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (belowBreakEven) ...[
            const SizedBox(height: 14),
            _WarningChip(text: S.belowBreakEven),
          ],
        ],
      ),
    );
  }

  Widget _buildFuelReceiptsBreakdown() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dialog,
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.fuelReceiptsTitle,
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              color: AppColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
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
                  onDeleteReceipt?.call(receipt.id);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '  ${i + 1}. ',
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          color: _gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${S.formatReceiptTimestamp(receipt.timestamp)} — ${formatPln(receipt.amountPaid)} PLN',
                          style: const TextStyle(
                            fontFamily: AppFonts.dmSans,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (onDeleteReceipt != null)
                        AppTapTarget(
                          onTap: () => onDeleteReceipt?.call(receipt.id),
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
            child: Divider(color: Colors.white24, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  S.totalPumpPaid,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: AppColors.mutedText,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${formatPln(entry.fuelPumpPaidTotal)} PLN',
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
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
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: AppColors.mutedText,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '-${formatPln(entry.fuelAfterDiscount)} PLN',
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: _crimson,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Divider(color: Color(0x14FFFFFF), height: 1),
  );

  Widget _line(
    String label,
    double value, {
    bool income = false,
    bool bold = false,
    bool showSign = true,
    Color? color,
  }) {
    final resolved = color ?? (income ? _emerald : _crimson);
    final prefix = (showSign && value > 0) ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: bold ? Colors.white : AppColors.mutedText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$prefix${formatPln(value)} PLN',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: AppFonts.jetBrainsMono,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: bold ? Colors.white : resolved,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
                color: selected ? _emerald : AppColors.cardBorderColor,
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
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatPln(entry.netProfit)} PLN · ${entry.tripCount} ${S.tripCount}',
                        style: const TextStyle(
                          fontFamily: AppFonts.jetBrainsMono,
                          fontSize: 11,
                          color: AppColors.mutedText,
                        ),
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
                      style: TextStyle(
                        fontFamily: AppFonts.dmSans,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1,
                      ),
                    ),
                    Text(
                      S.perHour,
                      style: TextStyle(
                        fontFamily: AppFonts.dmSans,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color.withValues(alpha: 0.6),
                        letterSpacing: 0.5,
                      ),
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
  late final TextEditingController _tripsCtrl;
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
    _tripsCtrl = TextEditingController(text: e != null ? '${e.tripCount}' : '');
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
      _tripsCtrl,
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

  String _num(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  /// Parses a money/decimal field, clamping negatives to 0. The input
  /// formatters already block a typed minus sign; this is a defensive backstop
  /// so a negative can never reach the calculations.
  double _parse(TextEditingController c) {
    final t = c.text
        .trim()
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
    _tripsCtrl.dispose();
    _fuelReceiptsNotifier.dispose();
    super.dispose();
  }

  bool _saved = false;

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
      tripCount: _parseInt(_tripsCtrl),
      hasRentalDiscount: _hasRentalDiscount,
      fuelReceipts: _fuelReceipts,
    );
    Navigator.of(context).pop(entry);
  }

  /// Rental tier bracket for the currently entered trip count and mode.
  RentalTier _rentalTier() =>
      expectedRentalTier(_parseInt(_tripsCtrl), _formDriverMode);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.existing == null ? S.addWeek : S.editWeek,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, _kMinTouchTarget),
            ),
            child: Text(
              S.save,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: _emerald,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
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
                _tripsCtrl,
                S.tripCountLabel,
                integer: true,
                required: true,
                positive: true,
                helper: _formDriverMode == DriverMode.paired
                    ? S.pairedTripsHint
                    : null,
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
              Row(
                children: [
                  Expanded(
                    child: _numField(
                      _hoursCtrl,
                      S.hoursShort,
                      integer: true,
                      dense: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _numField(
                      _minutesCtrl,
                      S.minutesShort,
                      integer: true,
                      dense: true,
                    ),
                  ),
                ],
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
                    tripCount: _parseInt(_tripsCtrl),
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
            Icons.lock_outline_rounded,
            size: 16,
            color: AppColors.labelText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _weekRangeLabel(widget.weekStart, widget.weekEnd),
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
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
      style: const TextStyle(
        fontFamily: AppFonts.dmSans,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: AppColors.labelText,
      ),
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
            backgroundColor: AppColors.elevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: Colors.white,
                fontSize: 18,
              ),
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
                  color: _gold,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: _gold),
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
                  backgroundColor: _gold,
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
                    icon: const Icon(Icons.add_rounded, size: 18, color: _gold),
                    label: Text(
                      S.addReceipt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.dmSans,
                        color: _gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (receipts.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.dialog,
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AppEmptyState(
                  compact: true,
                  accent: _gold,
                  icon: Icons.local_gas_station_outlined,
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
                  color: AppColors.dialog,
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _LazyReceiptList(
                      itemCount: receipts.length,
                      estimatedItemExtent: 72,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Colors.white10, height: 1),
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
                            _fuelReceiptsNotifier.value =
                                _fuelReceiptsNotifier.value
                                    .where((r) => r.id != item.id)
                                    .toList();
                          },
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                            leading: CircleAvatar(
                              radius: 13,
                              backgroundColor: _gold.withValues(alpha: 0.15),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  fontFamily: AppFonts.dmSans,
                                  color: _gold,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              '${formatPln(item.amountPaid)} PLN',
                              style: const TextStyle(
                                fontFamily: AppFonts.dmSans,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              S.formatReceiptTimestamp(item.timestamp),
                              style: const TextStyle(
                                fontFamily: AppFonts.dmSans,
                                color: AppColors.mutedText,
                                fontSize: 12,
                              ),
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
                    const Divider(color: Colors.white24, height: 1),
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
                                  style: const TextStyle(
                                    fontFamily: AppFonts.dmSans,
                                    color: AppColors.mutedText,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${formatPln(totalPaid)} PLN',
                                maxLines: 1,
                                style: const TextStyle(
                                  fontFamily: AppFonts.dmSans,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
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
                                  style: const TextStyle(
                                    fontFamily: AppFonts.dmSans,
                                    color: _emerald,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${formatPln(discounted)} PLN',
                                maxLines: 1,
                                style: const TextStyle(
                                  fontFamily: AppFonts.dmSans,
                                  color: _emerald,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
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
  /// pump-paid field (× 0.90 discount) plus the rental toggle / trip count, so
  /// the driver sees — updated on every keystroke — the turnover they have to
  /// clear this week before the week pays for itself.
  Widget _breakEvenReference() {
    final threshold = calculateBreakEven(
      fixedCosts: _currentFuelAfterDiscount() + _currentRentalFee(),
    );
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, size: 15, color: _amber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              S.breakEvenLabel(formatPln(threshold)),
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _amber,
                height: 1.3,
              ),
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
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
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
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
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
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _crimson,
            ),
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
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(7),
              ],
        style: const TextStyle(
          fontFamily: AppFonts.dmSans,
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        validator: (v) => _validateField(
          v,
          required: required,
          positive: positive,
          maxVal: maxVal,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: AppColors.mutedText,
            fontSize: 14,
          ),
          helperText: helper,
          helperMaxLines: 3,
          helperStyle: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: AppColors.labelText,
            fontSize: 11,
            height: 1.3,
          ),
          suffixText: suffix,
          suffixStyle: const TextStyle(
            fontFamily: AppFonts.jetBrainsMono,
            color: AppColors.labelText,
            fontSize: 13,
          ),
          filled: true,
          fillColor: _cardColor,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: dense ? 14 : 18,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: _cardRadius,
            borderSide: const BorderSide(color: AppColors.cardBorderColor, width: 1),
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
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: _cardColor,
          border: _cardBorder,
          borderRadius: _cardRadius,
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_rounded, size: 20, color: _emerald),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.labelText),
          ],
        ),
      ),
    );
  }
}

class _FreeWeekProgressCard extends StatelessWidget {
  const _FreeWeekProgressCard({
    required this.lifetimeTrips,
    required this.onReset,
    required this.onEdit,
  });

  final int lifetimeTrips;
  final VoidCallback onReset;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final progress = calculateCurrentFreeWeekProgress(lifetimeTrips);
    final earned = calculateFreeWeeksEarned(lifetimeTrips);
    final frac = (progress / kFreeWeekTripThreshold).clamp(0.0, 1.0);

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
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AppTapTarget(
                onTap: onEdit,
                tooltip: S.editLifetimeTripsTitle,
                child: const Icon(Icons.edit_outlined, size: 20, color: _gold),
              ),
              AppTapTarget(
                onTap: onReset,
                tooltip: S.resetLifetimeTripsTitle,
                child: const Icon(Icons.restart_alt, size: 20, color: _gold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              backgroundColor: AppColors.track,
              valueColor: const AlwaysStoppedAnimation<Color>(_gold),
              minHeight: 6,
            ),
          ),
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
                  Expanded(
                    child: Text(
                      earned > 1
                          ? S.freeWeekRewardBadgeCount(earned)
                          : S.freeWeekRewardBadge,
                      style: const TextStyle(
                        fontFamily: AppFonts.dmSans,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _gold,
                      ),
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
