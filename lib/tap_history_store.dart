import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log.dart';

/// Append-only NDJSON log of overlay taps.
///
/// Kept out of SharedPreferences so each tap does not rewrite the ~47 KB
/// prefs XML. Capped at [maxEntries]; compaction rewrites only when the
/// file grows past that.
class TapHistoryStore {
  TapHistoryStore({File? file}) : _fileOverride = file;

  static TapHistoryStore instance = TapHistoryStore();

  static const int maxEntries = 500;

  /// How far past [maxEntries] the file is allowed to grow before a rewrite.
  /// Compaction reads + re-encodes every line, so trimming on the exact
  /// boundary would pay that cost on every tap once the log is full. The
  /// slack amortizes it to one rewrite per [_compactSlack] taps; readers
  /// still never see more than [maxEntries] because [_readAllNow] trims.
  static const int _compactSlack = 100;

  static const String prefsKey = 'tapHistory';
  static const String fileName = 'tap_history.jsonl';

  final File? _fileOverride;
  File? _file;
  Future<void> _queue = Future<void>.value();

  /// Cached line count so the tap hot path never parses the whole file.
  /// `null` means "not known yet" — resolved once, then kept in sync by
  /// append/compact/clear. Drift is self-correcting: every full parse
  /// rewrites it, and a stale value only shifts when compaction runs.
  int? _entryCount;

  @visibleForTesting
  static void resetInstanceForTest({File? file}) {
    instance = TapHistoryStore(file: file);
  }

  Future<File> _resolve() async {
    final override = _fileOverride;
    if (override != null) return override;
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}${Platform.pathSeparator}$fileName');
    return _file!;
  }

  static String formatLocalTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Future<void> _enqueue(Future<void> Function() job) {
    final run = _queue.then((_) => job());
    _queue = run.catchError((Object e, StackTrace s) {
      loge(
        'tap history queue failed',
        name: 'tap_store',
        error: e,
        stack: s,
      );
    });
    return run;
  }

  Future<void> append(String type, {DateTime? at}) {
    return _enqueue(() => _appendNow(type, at ?? DateTime.now()));
  }

  Future<void> _appendNow(String type, DateTime now) async {
    final entry = <String, String>{
      'type': type,
      'timestamp': now.toIso8601String(),
      'localTime': formatLocalTime(now),
    };
    final file = await _resolve();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
      flush: false,
    );

    final known = _entryCount;
    _entryCount = known != null ? known + 1 : (await _parseFile(file)).length;
    await _compactIfNeeded(file);
  }

  Future<List<Map<String, dynamic>>> readAll() {
    return _enqueue(_readAllNow).then((_) => _lastRead);
  }

  List<Map<String, dynamic>> _lastRead = const [];

  Future<void> _readAllNow() async {
    final file = await _resolve();
    final all = await _parseFile(file);
    _entryCount = all.length;
    // The file may carry up to [_compactSlack] extra lines between
    // compactions; readers always see the capped window.
    _lastRead = all.length > maxEntries
        ? all.sublist(all.length - maxEntries)
        : all;
  }

  /// Newest first — same order the history sheet expects.
  Future<List<Map<String, dynamic>>> readNewestFirst() async {
    final all = await readAll();
    return all.reversed.toList();
  }

  Future<void> clear() {
    return _enqueue(_clearNow);
  }

  Future<void> _clearNow() async {
    final file = await _resolve();
    try {
      if (await file.exists()) await file.writeAsString('');
    } catch (_) {}
    _entryCount = 0;
    _lastRead = const [];
  }

  /// One-time move of the old JSON-array prefs blob onto the NDJSON file.
  Future<void> migrateFromPrefs(SharedPreferences prefs) {
    return _enqueue(() => _migrateNow(prefs));
  }

  Future<void> _migrateNow(SharedPreferences prefs) async {
    final raw = prefs.getString(prefsKey);
    if (raw == null) return;

    List<dynamic> list;
    try {
      final decoded = jsonDecode(raw);
      list = decoded is List ? List<dynamic>.from(decoded) : <dynamic>[];
    } catch (_) {
      list = <dynamic>[];
    }

    if (list.isNotEmpty) {
      final file = await _resolve();
      await file.parent.create(recursive: true);
      final existing = await _parseFile(file);
      final merged = <Map<String, dynamic>>[
        ...existing,
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
      final keep = merged.length > maxEntries
          ? merged.sublist(merged.length - maxEntries)
          : merged;
      await _writeAll(file, keep);
    }

    await prefs.remove(prefsKey);
  }

  Future<List<Map<String, dynamic>>> _parseFile(File file) async {
    if (!await file.exists()) return [];
    final raw = await file.readAsString();
    if (raw.isEmpty) return [];
    final out = <Map<String, dynamic>>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          out.add(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return out;
  }

  Future<void> _compactIfNeeded(File file) async {
    if ((_entryCount ?? 0) <= maxEntries + _compactSlack) return;
    final entries = await _parseFile(file);
    if (entries.length <= maxEntries) {
      _entryCount = entries.length;
      return;
    }
    await _writeAll(file, entries.sublist(entries.length - maxEntries));
  }

  Future<void> _writeAll(File file, List<Map<String, dynamic>> entries) async {
    final buf = StringBuffer();
    for (final e in entries) {
      buf.writeln(jsonEncode(e));
    }
    await file.writeAsString(buf.toString());
    _entryCount = entries.length;
  }
}
