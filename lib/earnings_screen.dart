import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'earnings_models.dart';
import 'earnings_pdf_export.dart';
import 'earnings_reminders.dart';
import 'l10n.dart';

const kDriverNameKey = 'driver_name';

const _cardColor = Color(0xFF1A1A1A);
const _emerald = Color(0xFF10B981);
const _crimson = Color(0xFFEF4444);
const _amber = Color(0xFFF59E0B);
final _cardBorder = Border.all(color: const Color(0x0DFFFFFF), width: 1);
final _cardRadius = BorderRadius.circular(16);

/// PLN/hour above which the hourly rate is considered "good" (green).
const double _goodHourlyThreshold = 30.0;

/// Gold accent used for the record badges.
const _gold = Color(0xFFFFD54A);

/// Chart / summary granularity selectable from the segmented control.
enum _ViewMode { weekly, monthly, yearly }

/// Max number of weeks shown in the weekly trend chart. Fixed so the chart's
/// width/layout never grows as more history accumulates — older weeks stay
/// reachable via the history list below instead.
const int _trendWeekWindow = 8;

Future<void> showDriverModeDialog(BuildContext context, SharedPreferences prefs, VoidCallback onModeChanged) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          S.driverModeDialogTitle,
          style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: activeDriverMode == DriverMode.solo ? const Color(0xFF242424) : Colors.transparent,
              leading: Icon(Icons.person_rounded, color: activeDriverMode == DriverMode.solo ? const Color(0xFFF59E0B) : Colors.white54),
              title: Text(
                S.driverModeSolo,
                style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: activeDriverMode == DriverMode.paired ? const Color(0xFF242424) : Colors.transparent,
              leading: Icon(Icons.people_rounded, color: activeDriverMode == DriverMode.paired ? const Color(0xFFF59E0B) : Colors.white54),
              title: Text(
                S.driverModePaired,
                style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
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

  /// When true (e.g. launched from the Monday reminder), the "add new week"
  /// form for the current week opens automatically after the first load.
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
    final entries = decodeEarnings(prefs.getString(kEarningsHistoryKey))
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
    if (!mounted) return;
    if (entries.isNotEmpty) {
      final latest = entries.first.weekStart;
      _historyFilterMonth ??=
          DateTime(latest.year, latest.month, 1);
    }
    final modeStr = prefs.getString(DriverMode.key);
    activeDriverMode = modeStr == 'paired' ? DriverMode.paired : DriverMode.solo;

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

  /// Replaces the entry list and refreshes the memoized monthly/yearly rollups.
  /// The only place [_entries] should be reassigned, so the caches never drift.
  /// Note: _cachedLifetimeTrips is NOT recomputed here — it is loaded from the
  /// persisted SharedPreferences odometer and updated only on new/edited saves.
  void _setEntries(List<WeekEarning> entries) {
    _entries = entries;
    _months = aggregateByMonth(entries);
    _years = aggregateByYear(entries);
  }

  /// Distinct calendar months present in [_entries], oldest → newest.
  List<DateTime> _historyMonths() {
    final seen = <String, DateTime>{};
    for (final e in _entries) {
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
    final months = _historyMonths();
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
        .where((e) =>
            e.weekStart.year == month.year && e.weekStart.month == month.month)
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
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          S.resetLifetimeTripsTitle,
          style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          S.resetLifetimeTripsConfirm,
          style: GoogleFonts.dmSans(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.cancel, style: GoogleFonts.dmSans(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              S.resetLifetimeTrips,
              style: GoogleFonts.dmSans(color: const Color(0xFFE57373), fontWeight: FontWeight.bold),
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
    final controller = TextEditingController(text: _cachedLifetimeTrips.toString());
    final newCount = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          S.editLifetimeTripsTitle,
          style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              S.editLifetimeTripsDesc,
              style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.dmSans(color: Colors.white),
              decoration: InputDecoration(
                labelText: S.editLifetimeTripsLabel,
                labelStyle: GoogleFonts.dmSans(color: Colors.white54),
                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFFFD700))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.cancel, style: GoogleFonts.dmSans(color: Colors.white54)),
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
              style: GoogleFonts.dmSans(color: const Color(0xFFFFD700), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (newCount != null) {
      final prefs = await _getPrefs();
      await prefs.setInt(kLifetimeTripsKey, newCount);
      if (mounted) {
        setState(() => _cachedLifetimeTrips = newCount);
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
  List<WeekEarning> _trendWeeks() {
    final weeks = _entries.reversed.toList();
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
        ..removeWhere((e) =>
            e.id == result.id || isSameDate(e.weekStart, result.weekStart))
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
          style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Text(
          S.deleteWeekConfirm,
          style: GoogleFonts.dmSans(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(S.cancel, style: GoogleFonts.dmSans(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              S.delete,
              style: GoogleFonts.dmSans(color: _crimson, fontWeight: FontWeight.w900),
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

  Future<void> _quickAddFuel() async {
    final ctrl = TextEditingController();
    final added = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            S.quickAddFuelTitle,
            style: GoogleFonts.dmSans(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.dmSans(color: Colors.white, fontSize: 18),
            autofocus: true,
            decoration: InputDecoration(
              labelText: S.amountPaidLabel,
              labelStyle: GoogleFonts.dmSans(color: Colors.white54),
              suffixText: 'PLN',
              suffixStyle: GoogleFonts.dmSans(color: _gold),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _gold),
              ),
            ),
            onSubmitted: (_) {
              final val = double.tryParse(ctrl.text.replaceAll(',', '.').trim());
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
                style: GoogleFonts.dmSans(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                final val = double.tryParse(ctrl.text.replaceAll(',', '.').trim());
                if (val != null && val > 0) {
                  Navigator.of(ctx).pop(val);
                }
              },
              child: Text(
                S.add,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

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
        fuelReceipts: [...currentEntry.fuelReceipts, newReceipt],
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
        acceptanceRateReported: null,
        cancellationRateReported: null,
        fuelReceipts: [newReceipt],
      );
    }

    setState(() {
      final nextList = [..._entries]
        ..removeWhere((e) =>
            e.id == nextEntry.id || isSameDate(e.weekStart, nextEntry.weekStart))
        ..add(nextEntry)
        ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
      _setEntries(nextList);
    });
    await _persist();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF2C2C2C),
        behavior: SnackBarBehavior.floating,
        content: Text(
          S.fuelAddedConfirmation(formatPln(added), nextEntry.fuelReceipts.length),
          style: GoogleFonts.dmSans(color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _deleteReceiptFromEntry(WeekEarning entry, String receiptId) async {
    final nextReceipts = entry.fuelReceipts.where((r) => r.id != receiptId).toList();
    final nextEntry = entry.copyWith(fuelReceipts: nextReceipts);
    setState(() {
      final nextList = [..._entries]
        ..removeWhere((e) => e.id == nextEntry.id || isSameDate(e.weekStart, nextEntry.weekStart))
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
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w800),
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          S.earningsTitle,
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          IconButton(
            tooltip: S.exportPdf,
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onPressed: _entries.isEmpty ? null : _exportPdf,
          ),
          IconButton(
            tooltip: S.reminderSettingsTitle,
            icon: const Icon(Icons.notifications_active_rounded),
            onPressed: _showReminderSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _emerald))
          : SafeArea(
              top: false,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: _buildSlivers(),
              ),
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
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          S.driverNamePrompt,
          style: GoogleFonts.dmSans(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.dmSans(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            labelText: S.driverNameLabel,
            labelStyle: GoogleFonts.dmSans(color: Colors.white54),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0x33FFFFFF)),
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
              style: GoogleFonts.dmSans(color: _emerald, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return null;

    final prefs = await _getPrefs();
    await prefs.setString(kDriverNameKey, result);
    if (mounted) setState(() => _driverName = result);
    return result;
  }

  /// Prompts for a range (Bu Ay / Bu Yıl / Tüm Zamanlar), then builds and
  /// shares a plain PDF earnings report for the weeks in that range.
  Future<void> _exportPdf() async {
    final choice = await showModalBottomSheet<_ExportRange>(
      context: context,
      backgroundColor: const Color(0xFF121212),
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
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: Colors.white38,
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
            _entries, DateTime(now.year, now.month, 1));
        rangeLabel = S.rangeThisMonth;
      case _ExportRange.specificMonth:
        final picked = await _pickExportMonth();
        if (picked == null || !mounted) return;
        weeks = EarningsPdfExport.weeksForMonth(_entries, picked);
        rangeLabel = _monthTitle(picked);
      case _ExportRange.thisYear:
        weeks =
            _entries.where((e) => e.weekStart.year == now.year).toList();
        rangeLabel = S.rangeThisYear;
      case _ExportRange.allTime:
        weeks = [..._entries];
        rangeLabel = S.rangeAllTime;
    }

    if (weeks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.exportNoData),
          backgroundColor: _cardColor,
        ),
      );
      return;
    }

    var driverName = _driverName;
    if (driverName.trim().isEmpty) {
      driverName = await _editDriverName() ?? '';
      if (!mounted) return;
    }

    await EarningsPdfExport.generateAndShare(
      weeks,
      rangeLabel: rangeLabel,
      driverName: driverName,
    );
  }

  /// Bottom sheet listing every month that actually has recorded weeks (from the
  /// memoized [_months] rollup), newest first, e.g. "Haziran 2026". Returns the
  /// first-of-month [DateTime] the user picks, or null if dismissed.
  Future<DateTime?> _pickExportMonth() {
    final monthsNewestFirst = _months.reversed.toList();
    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: const Color(0xFF121212),
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
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: Colors.white38,
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

  /// Bottom sheet with the "Pazartesi Hatırlatması" on/off switch.
  Future<void> _showReminderSettings() async {
    final prefs = await _getPrefs();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ReminderSettingsSheet(prefs: prefs),
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
              GestureDetector(
                onTap: () async {
                  final prefs = await _getPrefs();
                  if (!mounted) return;
                  await showDriverModeDialog(context, prefs, () {
                    if (mounted) setState(() {});
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    S.driverModeLabel(activeDriverMode == DriverMode.paired),
                    style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70),
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

    return [
      if (_trendWeeks().length >= 2)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _TrendChart(
              weeks: _trendWeeks(),
              selectedStart: start,
              onBarTap: _selectWeek,
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _WeekSelector(
            label: _weekRangeLabel(start, end),
            canGoForward: canGoForward,
            onPrev: () => setState(() => _weekOffset -= 1),
            onNext:
                canGoForward ? () => setState(() => _weekOffset += 1) : null,
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
              onDeleteReceipt: (receiptId) => _deleteReceiptFromEntry(entry, receiptId),
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
                    onTap: () => _openForm(
                      existing: entry,
                      start: start,
                      end: end,
                    ),
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
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Text(
            S.history,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: Colors.white38,
            ),
          ),
        ),
      ),
      if (_entries.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: _HistoryMonthSelector(
              months: _historyMonths(),
              selected: activeHistoryMonth!,
              onSelected: (m) {
                HapticFeedback.selectionClick();
                setState(() => _historyFilterMonth = m);
              },
            ),
          ),
        ),
      if (_entries.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Text(
              S.noEarnings,
              style: GoogleFonts.dmSans(
                color: Colors.white54,
                fontSize: 15,
                height: 1.4,
              ),
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
    ];
  }

  List<Widget> _monthlySlivers() {
    final all = _months;
    if (all.isEmpty) return [_emptyStateSliver()];

    final recent =
        all.length > 12 ? all.sublist(all.length - 12) : all;
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
                  selected: m.month.year == selected.month.year &&
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
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: Colors.white38,
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
              selected: months[i].year == selected.year &&
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _emerald.withValues(alpha: 0.12) : const Color(0x0AFFFFFF),
          border: Border.all(
            color: selected
                ? _emerald.withValues(alpha: 0.45)
                : const Color(0x0DFFFFFF),
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? Colors.white : Colors.white38,
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
      child: Row(
        children: [
          Text(
            '${S.driverNameLabel}: ',
            style: GoogleFonts.dmSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white38,
            ),
          ),
          Flexible(
            child: Text(
              display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Colors.white70,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.edit_rounded, size: 13, color: Colors.white38),
        ],
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
              style: GoogleFonts.dmSans(
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
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Colors.white38,
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
                  style: GoogleFonts.dmSans(
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
                    style: GoogleFonts.dmSans(
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
      textStyle: GoogleFonts.dmSans(
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
                style: GoogleFonts.dmSans(
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
    final maxRate = weeks.fold<double>(
      0,
      (m, w) => math.max(m, w.hourlyRate),
    );
    final safeMax = maxRate > 0 ? maxRate : 1.0;

    final n = weeks.length;
    final last4 = weeks.sublist(math.max(0, n - 4));
    final prev4 = n > 4 ? weeks.sublist(math.max(0, n - 8), n - 4) : <WeekEarning>[];
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
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  S.fourWeekAverage(formatPln(last4Avg)),
                  style: GoogleFonts.dmSans(
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
                      heightFactor:
                          (weeks[i].hourlyRate / safeMax).clamp(0.0, 1.0),
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
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: selected ? _emerald : Colors.white38,
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
              style: GoogleFonts.jetBrainsMono(
                fontSize: 8,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white70 : Colors.white24,
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
          height: 36,
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
            style: GoogleFonts.dmSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : Colors.white54,
            ),
            child: Text(label),
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
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Colors.white38,
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
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.totalNetProfit,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Colors.white38,
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
                  style: GoogleFonts.dmSans(
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
                    style: GoogleFonts.dmSans(
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
              _stat('${formatPln(avgHourlyRate)} ${S.perHour}', S.avgHourlyRate),
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
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white38,
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
                style: GoogleFonts.dmSans(
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
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white54,
              ),
            )
          else ...[
            Text(
              _weekRangeLabel(best.weekStart, best.weekEnd),
              style: GoogleFonts.dmSans(
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
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Colors.white38,
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
              border: Border.all(color: const Color(0x0DFFFFFF), width: 1),
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
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatPln(summary.totalNetProfit)} PLN · ${S.weekCountLabel(summary.weekCount)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: Colors.white54,
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
                      style: GoogleFonts.dmSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1,
                      ),
                    ),
                    Text(
                      S.perHour,
                      style: GoogleFonts.dmSans(
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
            child: const Icon(
              Icons.savings_rounded,
              size: 30,
              color: _emerald,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            S.noEarnings,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              color: Colors.white54,
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
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: filled ? Colors.white : _emerald,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconOnlyButton extends StatelessWidget {
  const _IconOnlyButton({required this.icon, required this.color, required this.onTap});

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

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.entry, this.breakEven, this.onDeleteReceipt});

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
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Colors.white38,
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
                style: GoogleFonts.dmSans(fontSize: 11, color: Colors.white38, fontStyle: FontStyle.italic),
              ),
            ),
          if (entry.fuelReceipts.isEmpty)
            _line(S.fuelDiscounted, -entry.fuelAfterDiscount)
          else
            _buildFuelReceiptsBreakdown(),
          _line(S.vat, -entry.vat),
          _line(S.settlementFee, -entry.settlementFee),
          _divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  S.netProfit,
                  style: GoogleFonts.dmSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                '${formatPln(entry.netProfit)} PLN',
                style: GoogleFonts.dmSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: entry.netProfit >= 0 ? _emerald : _crimson,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _line('🏦 ${S.bankDeposit}', entry.bankDeposit,
              color: entry.bankDeposit >= 0 ? _emerald : _crimson, showSign: false),
          _line('💵 ${S.cashInHand}', entry.cashInHand,
              color: _amber, showSign: false),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  S.hourlyRate,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white54,
                  ),
                ),
              ),
              Text(
                '${formatPln(entry.hourlyRate)} ${S.perHour}',
                style: GoogleFonts.jetBrainsMono(
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
        color: const Color(0xFF161616),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            S.fuelReceiptsTitle,
            style: GoogleFonts.dmSans(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < entry.fuelReceipts.length; i++) ...[
            Dismissible(
              key: ValueKey(entry.fuelReceipts[i].id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 8),
                color: _crimson.withValues(alpha: 0.2),
                child: const Icon(Icons.delete_outline_rounded, color: _crimson, size: 18),
              ),
              onDismissed: (_) {
                onDeleteReceipt?.call(entry.fuelReceipts[i].id);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '  ${i + 1}. ',
                      style: GoogleFonts.dmSans(
                        color: _gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${S.formatReceiptTimestamp(entry.fuelReceipts[i].timestamp)} — ${formatPln(entry.fuelReceipts[i].amountPaid)} PLN',
                        style: GoogleFonts.dmSans(color: Colors.white, fontSize: 13),
                      ),
                    ),
                    if (onDeleteReceipt != null)
                      GestureDetector(
                        onTap: () => onDeleteReceipt?.call(entry.fuelReceipts[i].id),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(color: Colors.white24, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                S.totalPumpPaid,
                style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${formatPln(entry.fuelPumpPaidTotal)} PLN',
                style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                S.totalFuelDiscounted,
                style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '-${formatPln(entry.fuelAfterDiscount)} PLN',
                style: GoogleFonts.dmSans(
                  color: _crimson,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
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
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: bold ? Colors.white : const Color(0xAAFFFFFF),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$prefix${formatPln(value)} PLN',
            textAlign: TextAlign.right,
            style: GoogleFonts.jetBrainsMono(
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
                color: selected ? _emerald : const Color(0x0DFFFFFF),
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
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatPln(entry.netProfit)} PLN · ${entry.tripCount} ${S.tripCount}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: Colors.white54,
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
                      style: GoogleFonts.dmSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1,
                      ),
                    ),
                    Text(
                      S.perHour,
                      style: GoogleFonts.dmSans(
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
  late final TextEditingController _acceptanceRateCtrl;
  late final TextEditingController _cancellationRateCtrl;
  late final ValueNotifier<List<FuelReceipt>> _fuelReceiptsNotifier;
  List<FuelReceipt> get _fuelReceipts => _fuelReceiptsNotifier.value;
  DriverMode get _formDriverMode => widget.existing?.driverMode ?? activeDriverMode;

  double get _fuelPumpTotal => _fuelReceipts.fold(0.0, (sum, r) => sum + r.amountPaid);

  /// Set after a failed save when online time (hours + minutes) is missing;
  /// drives the inline "eksik veri" indicator under the online-time row.
  bool _onlineTimeMissing = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _netIncomeCtrl = TextEditingController(text: e != null ? _num(e.netIncome) : '');
    _cashCtrl = TextEditingController(text: e != null ? _num(e.cashReceived) : '');
    final hours = e?.onlineHours ?? 0;
    _hoursCtrl = TextEditingController(text: e != null ? '${hours.truncate()}' : '');
    _minutesCtrl = TextEditingController(
      text: e != null ? '${((hours - hours.truncate()) * 60).round()}' : '',
    );
    _tripsCtrl = TextEditingController(text: e != null ? '${e.tripCount}' : '');
    _acceptanceRateCtrl = TextEditingController(
      text: e?.acceptanceRateReported != null ? _num(e!.acceptanceRateReported!) : '',
    );
    _cancellationRateCtrl = TextEditingController(
      text: e?.cancellationRateReported != null ? _num(e!.cancellationRateReported!) : '',
    );
    final initialReceipts = List<FuelReceipt>.from(e?.fuelReceipts ?? []);
    if (initialReceipts.isEmpty && e != null && e.fuelPumpPaidTotal > 0) {
      initialReceipts.add(FuelReceipt(timestamp: e.weekStart, amountPaid: e.fuelPumpPaidTotal));
    }
    _fuelReceiptsNotifier = ValueNotifier<List<FuelReceipt>>(initialReceipts);

    // Any field feeding the live preview triggers a rebuild (net income drives
    // VAT; trips and rates drive the computed rental fee).
    for (final c in [
      _netIncomeCtrl,
      _hoursCtrl,
      _minutesCtrl,
      _tripsCtrl,
      _acceptanceRateCtrl,
      _cancellationRateCtrl,
      _cashCtrl,
    ]) {
      c.addListener(_onPreviewChanged);
    }
  }

  void _onPreviewChanged() {
    if (mounted) {
      setState(() {
        // Clear the stale online-time error as soon as valid time is entered.
        if (_onlineTimeMissing &&
            onlineHoursFromHm(_parseInt(_hoursCtrl), _parseInt(_minutesCtrl)) >
                0) {
          _onlineTimeMissing = false;
        }
      });
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
    final t = c.text.trim().replaceAll(' ', '').replaceAll('.', '').replaceAll(',', '.');
    if (t.isEmpty) return 0;
    final v = double.tryParse(t) ?? 0;
    return v < 0 ? 0 : v;
  }

  double? _parseNullable(TextEditingController c) {
    final t = c.text.trim().replaceAll(' ', '').replaceAll('.', '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    return v < 0 ? 0 : v;
  }

  /// Parses an integer field, clamping negatives to 0 (e.g. trip count).
  int _parseInt(TextEditingController c) {
    final v = int.tryParse(c.text.trim()) ?? 0;
    return v < 0 ? 0 : v;
  }

  @override
  void dispose() {
    for (final c in [
      _netIncomeCtrl,
      _hoursCtrl,
      _minutesCtrl,
      _tripsCtrl,
      _acceptanceRateCtrl,
      _cancellationRateCtrl,
      _cashCtrl,
    ]) {
      c.removeListener(_onPreviewChanged);
    }
    _netIncomeCtrl.dispose();
    _cashCtrl.dispose();
    _hoursCtrl.dispose();
    _minutesCtrl.dispose();
    _tripsCtrl.dispose();
    _acceptanceRateCtrl.dispose();
    _cancellationRateCtrl.dispose();
    _fuelReceiptsNotifier.dispose();
    super.dispose();
  }

  void _save() {
    final hours = onlineHoursFromHm(_parseInt(_hoursCtrl), _parseInt(_minutesCtrl));
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
      acceptanceRateReported: _parseNullable(_acceptanceRateCtrl),
      cancellationRateReported: _parseNullable(_cancellationRateCtrl),
      fuelReceipts: _fuelReceipts,
    );
    Navigator.of(context).pop(entry);
  }

  /// Rental tier bracket for the currently entered trip count and reported rates.
  RentalTier _rentalTier() => expectedRentalTier(
        _parseInt(_tripsCtrl),
        _parseNullable(_acceptanceRateCtrl),
        _parseNullable(_cancellationRateCtrl),
        _formDriverMode == DriverMode.paired ? RENTAL_TIERS_PAIRED : RENTAL_TIERS,
      );

  @override
  Widget build(BuildContext context) {
    // Live preview reuses the model's cross-check logic so the same warnings
    // shown here match the saved summary card.
    final preview = WeekEarning(
      id: 'preview',
      weekStart: widget.weekStart,
      weekEnd: widget.weekEnd,
      driverMode: _formDriverMode,
      netIncome: _parse(_netIncomeCtrl),
      cashReceived: _parse(_cashCtrl),
      onlineHours: onlineHoursFromHm(_parseInt(_hoursCtrl), _parseInt(_minutesCtrl)),
      tripCount: _parseInt(_tripsCtrl),
      acceptanceRateReported: _parseNullable(_acceptanceRateCtrl),
      cancellationRateReported: _parseNullable(_cancellationRateCtrl),
      fuelReceipts: _fuelReceipts,
    );
    final warnings = preview.warnings;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.existing == null ? S.addWeek : S.editWeek,
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              S.save,
              style: GoogleFonts.dmSans(
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
              _numField(_netIncomeCtrl, S.netIncome,
                  suffix: 'PLN',
                  required: true,
                  positive: true,
                  helper: S.netIncomeHint),
              _breakEvenReference(),
              _numField(_tripsCtrl, S.tripCountLabel,
                  integer: true, required: true, positive: true,
                  helper: _formDriverMode == DriverMode.paired ? S.pairedTripsHint : null),
              _numField(_acceptanceRateCtrl, S.acceptanceRateReported,
                  suffix: '%', required: true, positive: false, maxVal: 100.0, helper: S.acceptanceRateHint),
              _numField(_cancellationRateCtrl, S.cancellationRateReported,
                  suffix: '%', required: true, positive: false, maxVal: 100.0, helper: S.cancellationRateHint),
              _computedRentalDisplay(),
              const SizedBox(height: 12),
              _buildFuelReceiptsSection(),
              _numField(_cashCtrl, S.cashReceived, suffix: 'PLN'),
              _label(S.onlineTime),
              Row(
                children: [
                  Expanded(
                    child: _numField(_hoursCtrl, S.hoursShort,
                        integer: true, dense: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _numField(_minutesCtrl, S.minutesShort,
                        integer: true, dense: true),
                  ),
                ],
              ),
              if (_onlineTimeMissing) _inlineError(S.onlineTimeMissing),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 4),
                _WarningList(warnings: warnings),
              ],
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
          const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.white38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _weekRangeLabel(widget.weekStart, widget.weekEnd),
              style: GoogleFonts.dmSans(
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
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: Colors.white38,
          ),
        ),
      );

  Future<void> _addReceiptInline() async {
    final ctrl = TextEditingController();
    final added = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            S.quickAddFuelTitle,
            style: GoogleFonts.dmSans(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.dmSans(color: Colors.white, fontSize: 18),
            autofocus: true,
            decoration: InputDecoration(
              labelText: S.amountPaidLabel,
              labelStyle: GoogleFonts.dmSans(color: Colors.white54),
              suffixText: 'PLN',
              suffixStyle: GoogleFonts.dmSans(color: _gold),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _gold),
              ),
            ),
            onSubmitted: (_) {
              final val = double.tryParse(ctrl.text.replaceAll(',', '.').trim());
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
                style: GoogleFonts.dmSans(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                final val = double.tryParse(ctrl.text.replaceAll(',', '.').trim());
                if (val != null && val > 0) {
                  Navigator.of(ctx).pop(val);
                }
              },
              child: Text(
                S.add,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (added == null || added <= 0 || !mounted) return;
    _fuelReceiptsNotifier.value = [
      ..._fuelReceiptsNotifier.value,
      FuelReceipt(timestamp: DateTime.now(), amountPaid: added),
    ];
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
                _label(S.fuelReceiptsTitle),
                TextButton.icon(
                  onPressed: _addReceiptInline,
                  icon: const Icon(Icons.add_rounded, size: 18, color: _gold),
                  label: Text(
                    S.addReceipt,
                    style: GoogleFonts.dmSans(
                      color: _gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (receipts.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  S.noFuelReceipts,
                  style: GoogleFonts.dmSans(color: Colors.white54, fontSize: 13),
                ),
              )
            else ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < receipts.length; i++) ...[
                      if (i > 0) const Divider(color: Colors.white10, height: 1),
                      Dismissible(
                        key: ValueKey(receipts[i].id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: _crimson.withValues(alpha: 0.2),
                          child: const Icon(Icons.delete_outline_rounded, color: _crimson),
                        ),
                        onDismissed: (_) {
                          final item = receipts[i];
                          _fuelReceiptsNotifier.value = _fuelReceiptsNotifier.value
                              .where((r) => r.id != item.id)
                              .toList();
                        },
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: CircleAvatar(
                            radius: 13,
                            backgroundColor: _gold.withValues(alpha: 0.15),
                            child: Text(
                              '${i + 1}',
                              style: GoogleFonts.dmSans(
                                color: _gold,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            '${formatPln(receipts[i].amountPaid)} PLN',
                            style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            S.formatReceiptTimestamp(receipts[i].timestamp),
                            style: GoogleFonts.dmSans(color: Colors.white54, fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                            onPressed: () {
                              final item = receipts[i];
                              _fuelReceiptsNotifier.value = _fuelReceiptsNotifier.value
                                  .where((r) => r.id != item.id)
                                  .toList();
                            },
                          ),
                        ),
                      ),
                    ],
                    const Divider(color: Colors.white24, height: 1),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                S.totalPumpPaid,
                                style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 13),
                              ),
                              Text(
                                '${formatPln(totalPaid)} PLN',
                                style: GoogleFonts.dmSans(
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
                              Text(
                                S.totalFuelDiscounted,
                                style: GoogleFonts.dmSans(color: _emerald, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${formatPln(discounted)} PLN',
                                style: GoogleFonts.dmSans(
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
              style: GoogleFonts.dmSans(
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

  /// Read-only, formula-driven rental fee. Recomputes live from trip count,
  /// acceptance rate, and cancellation rate; there is no manual override.
  Widget _computedRentalDisplay() {
    final tier = _rentalTier();
    final label = S.rentalComputed(rentalTierRangeLabel(tier), formatPln(tier.fee));
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
              style: GoogleFonts.dmSans(
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
                style: GoogleFonts.dmSans(
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
  String? _validateField(String? v, {required bool required, required bool positive, double maxVal = 999999.0}) {
    final t = (v ?? '').trim().replaceAll(' ', '').replaceAll('.', '').replaceAll(',', '.');
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
        style: GoogleFonts.dmSans(
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
          labelStyle: GoogleFonts.dmSans(color: Colors.white54, fontSize: 14),
          helperText: helper,
          helperMaxLines: 3,
          helperStyle: GoogleFonts.dmSans(color: Colors.white38, fontSize: 11, height: 1.3),
          suffixText: suffix,
          suffixStyle: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 13),
          filled: true,
          fillColor: _cardColor,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: dense ? 14 : 18,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: _cardRadius,
            borderSide: const BorderSide(color: Color(0x0DFFFFFF), width: 1),
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
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet holding the "Pazartesi Hatırlatması" on/off switch. Persists
/// the flag and (re)schedules or cancels the weekly local notification.
class _ReminderSettingsSheet extends StatefulWidget {
  const _ReminderSettingsSheet({required this.prefs});

  final SharedPreferences prefs;

  @override
  State<_ReminderSettingsSheet> createState() => _ReminderSettingsSheetState();
}

class _ReminderSettingsSheetState extends State<_ReminderSettingsSheet> {
  late bool _enabled = EarningsReminders.isEnabled(widget.prefs);

  Future<void> _toggle(bool value) async {
    HapticFeedback.selectionClick();
    setState(() => _enabled = value);
    await EarningsReminders.setEnabled(widget.prefs, value);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
            GestureDetector(
              onTap: () => _toggle(!_enabled),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: _cardColor,
                  border: Border.all(
                    color: _enabled ? _emerald : const Color(0x0DFFFFFF),
                    width: _enabled ? 1.5 : 1,
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
                            S.reminderSettingsTitle,
                            style: GoogleFonts.dmSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            S.reminderSettingsBody,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white54,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: _enabled,
                      onChanged: _toggle,
                      activeThumbColor: Colors.white,
                      activeTrackColor: _emerald,
                      inactiveThumbColor: Colors.white70,
                      inactiveTrackColor: const Color(0x22FFFFFF),
                    ),
                  ],
                ),
              ),
            ),
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
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.edit_outlined, size: 17, color: _gold),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onReset,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _gold.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.restart_alt, size: 13, color: _gold),
                      const SizedBox(width: 4),
                      Text(
                        S.resetLifetimeTrips,
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _gold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              backgroundColor: const Color(0xFF2A2A2A),
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
                border: Border.all(color: _gold.withValues(alpha: 0.5), width: 1),
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
                      style: GoogleFonts.dmSans(
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

