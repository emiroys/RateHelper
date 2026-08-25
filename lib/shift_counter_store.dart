import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<void> _queue = Future<void>.value();
  ShiftCounters _last = const ShiftCounters();

  @visibleForTesting
  static void resetInstanceForTest({File? file}) {
    instance = ShiftCounterStore(file: file);
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
    _queue = _queue.then((_) => _readNow());
    return _queue.then((_) => _last);
  }

  Future<void> _readNow() async {
    _last = await _readFile(await _resolve()) ?? const ShiftCounters();
  }

  Future<void> write(ShiftCounters counters) {
    _queue = _queue.then((_) => _writeNow(counters));
    return _queue;
  }

  /// Overlay writes accepted/rejected/completed without clobbering canceled.
  Future<ShiftCounters> merge({
    int? accepted,
    int? rejected,
    int? completed,
    int? canceled,
  }) {
    _queue = _queue.then((_) async {
      final current = await _readFile(await _resolve()) ?? const ShiftCounters();
      final next = current.copyWith(
        accepted: accepted,
        rejected: rejected,
        completed: completed,
        canceled: canceled,
      );
      await _writeNow(next);
    });
    return _queue.then((_) => _last);
  }

  Future<void> _writeNow(ShiftCounters counters) async {
    final file = await _resolve();
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(counters.encode(), flush: false);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    try {
      await tmp.rename(file.path);
    } catch (_) {
      await file.writeAsString(counters.encode(), flush: false);
      try {
        await tmp.delete();
      } catch (_) {}
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
    _queue = _queue.then((_) => _migrateNow(prefs));
    return _queue;
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
