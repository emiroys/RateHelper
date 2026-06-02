import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'crash_logger.dart';

/// Debug-only log. In release this is a no-op: `adb logcat` shows
/// nothing about counter taps, overlay drags, permission flow, or any
/// other operational detail an attacker reading system logs could use
/// to fingerprint user behaviour.
void logd(String message, {String name = 'app'}) {
  if (kReleaseMode) return;
  developer.log(message, name: name);
}

/// Error log. In RELEASE: written to the internal-storage crash file
/// only — never to logcat. In DEBUG: also mirrored to `developer.log`
/// for fast iteration. Errors are not stripped from the file because
/// the user needs them to report bugs via WhatsApp.
void loge(
  String message, {
  String name = 'app',
  Object? error,
  StackTrace? stack,
}) {
  if (!kReleaseMode) {
    developer.log(message, name: name, error: error, stackTrace: stack);
  }
  unawaited(CrashLogger.appendError(name, message, error, stack));
}
