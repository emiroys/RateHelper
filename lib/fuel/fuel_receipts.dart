import 'package:shared_preferences/shared_preferences.dart';

import '../earnings_models.dart';
import '../services/backup_service.dart';

/// The current week's fuel receipts inside the earnings history, the same
/// rows the Earnings screen edits.
abstract final class FuelReceiptStore {
  static Future<List<FuelReceipt>> currentWeek({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await BackupService.recoverPendingRestoreIfNeeded(prefs: prefs);
    final monday = weekStartForOffset(0, now: now);
    for (final entry in _decode(prefs)) {
      if (isSameDate(entry.weekStart, monday)) {
        return List.of(entry.fuelReceipts);
      }
    }
    return const [];
  }

  /// Appends one receipt to this week (creating the week if needed) and
  /// returns how many receipts the week now holds.
  static Future<int> add(double amount, {DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await BackupService.recoverPendingRestoreIfNeeded(prefs: prefs);
    final clock = now ?? DateTime.now();
    final entries = _decode(prefs)
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
    final monday = weekStartForOffset(0, now: clock);
    final sunday = weekEndForStart(monday);
    final receipt = FuelReceipt(timestamp: clock, amountPaid: amount);

    final index = entries.indexWhere((e) => isSameDate(e.weekStart, monday));
    final int count;
    if (index >= 0) {
      final receipts = capFuelReceipts([
        ...entries[index].fuelReceipts,
        receipt,
      ]);
      count = receipts.length;
      entries[index] = entries[index].copyWith(fuelReceipts: receipts);
    } else {
      count = 1;
      entries.insert(
        0,
        WeekEarning(
          id: '${monday.millisecondsSinceEpoch}_${sunday.millisecondsSinceEpoch}',
          weekStart: monday,
          weekEnd: sunday,
          driverMode: DriverMode.parse(prefs.getString(DriverMode.key)),
          netIncome: 0,
          cashReceived: 0,
          onlineHours: 0,
          driverTripCount: 0,
          hasRentalDiscount: true,
          fuelReceipts: [receipt],
        ),
      );
    }
    await prefs.setString(kEarningsHistoryKey, encodeEarnings(entries));
    return count;
  }

  static List<WeekEarning> _decode(SharedPreferences prefs) => decodeEarnings(
    prefs.getString(kEarningsHistoryKey),
    onCorrupt: (raw) => prefs.setString(kEarningsCorruptBackupKey, raw),
  );
}
