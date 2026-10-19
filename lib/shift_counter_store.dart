import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log.dart';

/// In-memory snapshot of the shift counters.
class ShiftCounters {
  const ShiftCounters({
    this.accepted = 0,
    this.rejected = 0,
    this.completed = 0,
    this.canceled = 0,
  });

  final int accepted;
  final int rejected;
  final int completed;
  final int canceled;

  ShiftCounters copyWith({
    int? accepted,
    int? rejected,
    int? completed,
    int? canceled,
  }) {
    return ShiftCounters(
      accepted: accepted ?? this.accepted,
      rejected: rejected ?? this.rejected,
      completed: completed ?? this.completed,
      canceled: canceled ?? this.canceled,
    );
  }

  String encode() => jsonEncode(<String, int>{
    'a': accepted,
    'r': rejected,
    'c': completed,
    'k': canceled,
  });

  static ShiftCounters decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const ShiftCounters();
    return ShiftCounters(
      accepted: _asInt(decoded['a']),
      rejected: _asInt(decoded['r']),
      completed: _asInt(decoded['c']),
      canceled: _asInt(decoded['k']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  @override
  bool operator ==(Object other) {
    return other is ShiftCounters &&
        other.accepted == accepted &&
        other.rejected == rejected &&
        other.completed == completed &&
        other.canceled == canceled;
  }

  @override
  int get hashCode => Object.hash(accepted, rejected, completed, canceled);
}

/// Tiny dedicated file for the four shift counters.
///
/// One write replaces 3–4 `SharedPreferences.setInt` calls (each of which
/// `apply()`/`fsync`s the whole prefs XML). Both isolates read this file
/// directly, so the main isolate never needs `prefs.reload()` to see overlay
/// taps.
class ShiftCounterStore {
  ShiftCounterStore({File? file}) : _fileOverride = file;

  static ShiftCounterStore instance = ShiftCounterStore();

  static const String fileName = 'shift_counters.json';
  static const String prefsKeyAccepted = 'acceptedRequests';
  static const String prefsKeyRejected = 'rejectedRequests';
  static const String prefsKeyCompleted = 'completedTrips';
  static const String prefsKeyCanceled = 'canceledTrips';

  static const List<String> prefsKeys = [
    prefsKeyAccepted,
    prefsKeyRejected,
    prefsKeyCompleted,
    prefsKeyCanceled,
  ];

  final File? _fileOverride;
  File? _file;
  Future<void>? _queue;
  ShiftCounters _last = const ShiftCounters();

  /// Chains [job] onto the store queue. A thrown job never poisons later
  /// writes: [_queue] recovers via [Future.catchError] at every link.
  Future<void> _enqueue(Future<void> Function() job) {
    final prev = _queue;
    final run = prev == null ? Future<void>.sync(job) : prev.then((_) => job());
    late final Future<void> guarded;
    guarded = run
        .catchError((Object e, StackTrace s) {
          loge(
            'shift counter queue failed',
            name: 'shift_store',
            error: e,
            stack: s,
          );
        })
        .whenComplete(() {
          if (identical(_queue, guarded)) {
            _queue = null;
          }
        });
    _queue = guarded;
    return run;
  }

  @visibleForTesting
  static void resetInstanceForTest({File? file, ShiftCounterStore? store}) {
    instance = store ?? ShiftCounterStore(file: file);
  }

  Future<File> _resolve() async {
    final override = _fileOverride;
    if (override != null) return override;
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}${Platform.pathSeparator}$fileName');
    return _file!;
  }

  Future<ShiftCounters> read() {
    return _enqueue(_readNow).then((_) => _last);
  }

  Future<void> _readNow() async {
    _last = await _readFile(await _resolve()) ?? const ShiftCounters();
  }

  Future<void> write(ShiftCounters counters) {
    return _enqueue(() => _writeNow(counters));
  }

  /// Writes [counters] with `flush: true` and verifies the on-disk content
  /// matches before completing. Throws [FileSystemException] if verification
  /// fails.
  Future<void> writeVerified(ShiftCounters counters) async {
    if (runtimeType != ShiftCounterStore) {
      await write(counters);
      final actual = await read();
      if (actual != counters) {
        throw const FileSystemException(
          'Shift counter write verification failed',
        );
      }
      return;
    }
    await _enqueue(() => _writeNow(counters, flush: true));
    final actual = await _verifyReadBack();
    if (actual != counters) {
      throw const FileSystemException('Shift counter write verification failed');
    }
  }

  /// Adds signed deltas to whatever is currently on disk, as a single queued
  /// read-modify-write. Both isolates write counters only through here: an
  /// absolute write computed from an isolate's in-memory view would erase
  /// whatever the other isolate added since that view was taken.
  Future<ShiftCounters> applyDelta({
    int acceptedDelta = 0,
    int rejectedDelta = 0,
    int completedDelta = 0,
    int canceledDelta = 0,
    int max = 99999,
  }) {
    return _enqueue(() async {
      final current = await _readFile(await _resolve()) ?? const ShiftCounters();
      await _writeNow(ShiftCounters(
        accepted: (current.accepted + acceptedDelta).clamp(0, max),
        rejected: (current.rejected + rejectedDelta).clamp(0, max),
        completed: (current.completed + completedDelta).clamp(0, max),
        canceled: (current.canceled + canceledDelta).clamp(0, max),
      ));
    }).then((_) => _last);
  }

  /// Same as [applyDelta], but flushes the write to disk and verifies by
  /// reading back from disk before returning. Used when reconciling pending
  /// taps before backup/restore so taps are never acknowledged unless durable.
  Future<ShiftCounters> applyDeltaVerified({
    int acceptedDelta = 0,
    int rejectedDelta = 0,
    int completedDelta = 0,
    int canceledDelta = 0,
    int max = 99999,
  }) async {
    if (runtimeType != ShiftCounterStore) {
      final saved = await applyDelta(
        acceptedDelta: acceptedDelta,
        rejectedDelta: rejectedDelta,
        completedDelta: completedDelta,
        canceledDelta: canceledDelta,
        max: max,
      );
      final actual = await read();
      if (actual != saved) {
        throw const FileSystemException(
          'Shift counter delta verification failed',
        );
      }
      return actual;
    }
    late ShiftCounters expected;
    await _enqueue(() async {
      final file = await _resolve();
      final current = await _readFile(file) ?? const ShiftCounters();
      expected = ShiftCounters(
        accepted: (current.accepted + acceptedDelta).clamp(0, max),
        rejected: (current.rejected + rejectedDelta).clamp(0, max),
        completed: (current.completed + completedDelta).clamp(0, max),
        canceled: (current.canceled + canceledDelta).clamp(0, max),
      );
      await _writeNow(expected, flush: true);
    });
    final actual = await _verifyReadBack();
    if (actual != expected) {
      throw const FileSystemException(
        'Shift counter delta verification failed',
      );
    }
    return actual;
  }

  Future<ShiftCounters> _verifyReadBack() async {
    final file = await _resolve();
    final onDisk = await _readFile(file);
    if (onDisk == null) {
      throw const FileSystemException('Shift counter file missing after write');
    }
    return onDisk;
  }

  /// Per-isolate tag for temp file names. Home and the overlay each hold
  /// their own store (and queue), so a shared `.tmp` name let one isolate's
  /// rename publish or delete the other's half-written file.
  static final String _tmpTag =
      Random().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  static int _tmpSeq = 0;

  Future<void> _writeNow(ShiftCounters counters, {bool flush = false}) async {
    final file = await _resolve();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.$_tmpTag.${_tmpSeq++}.tmp');
    await tmp.writeAsString(counters.encode(), flush: flush);
    // rename(2) replaces the target atomically on Android, so the counters
    // file is never absent. Deleting first would open a window where a
    // process kill (Samsung battery manager is aggressive here) leaves no
    // file at all and the whole shift reads back as zero.
    try {
      await tmp.rename(file.path);
    } catch (_) {
      // Windows (test host) refuses rename onto an existing file.
      try {
        if (await file.exists()) await file.delete();
        await tmp.rename(file.path);
      } catch (_) {
        await file.writeAsString(counters.encode(), flush: flush);
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
    _last = counters;
  }

  Future<ShiftCounters?> _readFile(File file) async {
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return ShiftCounters.decode(raw);
    } catch (_) {
      return null;
    }
  }

  /// One-time move of the four prefs ints onto the dedicated file.
  Future<void> migrateFromPrefs(SharedPreferences prefs) {
    return _enqueue(() => _migrateNow(prefs));
  }

  Future<void> _migrateNow(SharedPreferences prefs) async {
    final hasPrefs = prefsKeys.any(prefs.containsKey);
    final file = await _resolve();
    final existing = await _readFile(file);

    if (existing != null) {
      if (hasPrefs) await _removePrefsKeys(prefs);
      _last = existing;
      return;
    }

    if (!hasPrefs) {
      _last = const ShiftCounters();
      return;
    }

    final migrated = ShiftCounters(
      accepted: prefs.getInt(prefsKeyAccepted) ?? 0,
      rejected: prefs.getInt(prefsKeyRejected) ?? 0,
      completed: prefs.getInt(prefsKeyCompleted) ?? 0,
      canceled: prefs.getInt(prefsKeyCanceled) ?? 0,
    );
    await _writeNow(migrated);
    await _removePrefsKeys(prefs);
  }

  Future<void> _removePrefsKeys(SharedPreferences prefs) async {
    for (final key in prefsKeys) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
  }
}
