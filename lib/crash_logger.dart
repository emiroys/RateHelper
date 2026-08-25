import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Writes uncaught Flutter / Dart errors to a plain-text file inside
/// the app's INTERNAL documents directory. Internal storage is fully
/// sandboxed by the Android kernel: only RateHelper (running under its
/// own UID) and root can read the file. No other app, regardless of
/// permissions, can access it.
///
/// Resolved at runtime via `path_provider.getApplicationDocumentsDirectory()`
/// which maps to `/data/data/<applicationId>/app_flutter/crash.log`.
/// This path is NOT enumerable from the system file picker — to read
/// it the user taps "Çökme Kayıtları" inside RateHelper and uses the
/// in-app "KOPYALA" button to share via WhatsApp.
///
/// Bounded at 64 KB; older content is dropped FIFO.
class CrashLogger {
  CrashLogger._();

  static const int _maxBytes = 64 * 1024;
  static const int _maxPerSecond = 5;
  static File? _file;
  static bool _initialised = false;
  static final List<DateTime> _recentWrites = <DateTime>[];
  static int _droppedThisWindow = 0;
  static Timer? _dropSummaryTimer;
  static Duration _dropSummaryDelay = const Duration(seconds: 1);
  static Future<void> _chain = Future<void>.value();

  static Future<void> install() async {
    if (_initialised) return;
    _initialised = true;

    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previous?.call(details);
      unawaited(
        _write(
          'FLUTTER',
          details.exceptionAsString(),
          details.exception,
          details.stack,
        ),
      );
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(_write('PLATFORM', error.toString(), error, stack));
      return true;
    };

    try {
      // Internal sandbox only. getExternalStorageDirectory() was rejected
      // because Android/data/<pkg>/files is world-readable to anything
      // with READ_EXTERNAL_STORAGE on pre-scoped-storage OEM forks, and
      // it shows up in the system file picker. The internal documents
      // directory is locked to our UID — no other app can open it.
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}crash.log');
    } catch (_) {
      _file = null;
    }
  }

  @visibleForTesting
  static void debugReset({File? file, Duration? dropSummaryDelay}) {
    _file = file;
    _initialised = true;
    _recentWrites.clear();
    _droppedThisWindow = 0;
    _dropSummaryTimer?.cancel();
    _dropSummaryTimer = null;
    _dropSummaryDelay = dropSummaryDelay ?? const Duration(seconds: 1);
    _chain = Future<void>.value();
  }

  @visibleForTesting
  static Future<void> flushDroppedSummaryForTest() {
    _dropSummaryTimer?.cancel();
    _dropSummaryTimer = null;
    _chain = _chain.then((_) => _writeDroppedSummary());
    return _chain;
  }

  static Future<void> appendError(
    String tag,
    String message,
    Object? error,
    StackTrace? stack,
  ) =>
      _write(tag, message, error, stack);

  static Future<File?> currentLogFile() async {
    if (_file != null && await _file!.exists()) return _file;
    return null;
  }

  static Future<void> clear() async {
    final f = _file;
    if (f == null) return;
    try {
      if (await f.exists()) await f.writeAsString('');
    } catch (_) {}
  }

  static Future<void> _write(
    String tag,
    String message,
    Object? error,
    StackTrace? stack,
  ) {
    _chain = _chain.then((_) => _writeNow(tag, message, error, stack));
    return _chain;
  }

  static bool _allowWrite(DateTime now) {
    _recentWrites.removeWhere(
      (t) => now.difference(t) >= const Duration(seconds: 1),
    );
    if (_recentWrites.length < _maxPerSecond) {
      _recentWrites.add(now);
      return true;
    }
    _droppedThisWindow++;
    _dropSummaryTimer ??= Timer(_dropSummaryDelay, () {
      _dropSummaryTimer = null;
      unawaited(_writeDroppedSummary());
    });
    return false;
  }

  static Future<void> _writeDroppedSummary() async {
    final n = _droppedThisWindow;
    _droppedThisWindow = 0;
    if (n <= 0) return;
    await _appendRaw('RATE_LIMIT', 'dropped $n', null, null);
  }

  static Future<void> _writeNow(
    String tag,
    String message,
    Object? error,
    StackTrace? stack,
  ) async {
    if (_file == null) return;
    if (!_allowWrite(DateTime.now())) return;
    await _appendRaw(tag, message, error, stack);
  }

  static Future<void> _appendRaw(
    String tag,
    String message,
    Object? error,
    StackTrace? stack,
  ) async {
    final f = _file;
    if (f == null) return;
    final ts = DateTime.now().toIso8601String();
    final buf = StringBuffer()
      ..writeln('--- [$ts] [$tag] ---')
      ..writeln(message);
    if (error != null && error.toString() != message) {
      buf.writeln('error: $error');
    }
    if (stack != null) buf.writeln(stack);

    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(
        buf.toString(),
        mode: FileMode.append,
        flush: false,
      );
      final size = await f.length();
      if (size > _maxBytes) {
        final all = await f.readAsString();
        final keep = all.substring(all.length - (_maxBytes ~/ 2));
        await f.writeAsString(keep);
      }
    } catch (_) {}
  }
}
