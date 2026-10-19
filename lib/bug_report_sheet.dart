import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';
import 'app_widgets.dart';
import 'bug_report_api.dart';
import 'crash_logger.dart';
import 'fonts.dart';
import 'l10n.dart';
import 'overlay_widget.dart';
import 'settings_screen.dart';

export 'bug_report_api.dart'
    show
        BugReportDiagnostics,
        BugReportSubmission,
        BugReportSubmitOutcome,
        BugScreenshotAttachment;

const MethodChannel _kBugReportSysChannel = MethodChannel(
  'com.ratehelper.app/system',
);

/// Issue categories available in the Bug Reporting sheet.
enum BugCategory {
  overlay,
  counters,
  earningsFuel,
  steeringNotification,
  other;

  String get label => switch (this) {
    BugCategory.overlay => S.reportCatOverlay,
    BugCategory.counters => S.reportCatCounters,
    BugCategory.earningsFuel => S.reportCatEarningsFuel,
    BugCategory.steeringNotification => S.reportCatSteeringNotification,
    BugCategory.other => S.reportCatOther,
  };
}

/// Result of invoking the native screenshot picker.
@immutable
class BugScreenshotPickResult {
  const BugScreenshotPickResult._({required this.status, this.attachment});

  const BugScreenshotPickResult.cancelled() : this._(status: 'cancelled');
  const BugScreenshotPickResult.tooLarge() : this._(status: 'too_large');
  const BugScreenshotPickResult.failed() : this._(status: 'failed');
  const BugScreenshotPickResult.ok(BugScreenshotAttachment attachment)
    : this._(status: 'ok', attachment: attachment);

  final String status;
  final BugScreenshotAttachment? attachment;
}

/// Deterministic privacy filter for crash logs and diagnostic excerpts.
///
/// Strips URLs, tokens/secrets, email addresses, phone numbers, GPS
/// coordinates, currency amounts, and local filesystem paths before any text
/// is shown in the preview or handed to the Android share sheet.
abstract final class BugReportSanitizer {
  static const int defaultMaxEntries = 5;
  static const int defaultMaxChars = 1800;

  // URLs (https, http, ws, wss) including query parameters / tokens.
  static final RegExp _urlPattern = RegExp(
    r'\b(?:https?|wss?)://[^\s"<>]+',
    caseSensitive: false,
  );

  // Email addresses.
  static final RegExp _emailPattern = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
  );

  // Bearer token header/value (e.g. `Authorization: Bearer abc.def` or `Bearer secret123`).
  static final RegExp _bearerPattern = RegExp(
    r'\b((?:authorization\s*[:=]\s*)?bearer)\s+([^\s,;"'
    "'"
    r']+)',
    caseSensitive: false,
  );

  // Key=value or header-style secret assignments (token, secret, key, password,
  // authorization, webhook, chat_id).
  static final RegExp _secretKeyValPattern = RegExp(
    r'\b(?:token|secret|api[_-]?key|password|passwd|authorization|webhook[_-]?secret|chat[_-]?id)\s*[:=]\s*([^\s,;]+)',
    caseSensitive: false,
  );

  // Telegram bot token shape (digits:alphanumeric).
  static final RegExp _telegramTokenPattern = RegExp(
    r'\b\d{7,12}:[A-Za-z0-9_-]{25,}\b',
  );

  // Long hex strings (≥32 chars, e.g. signing hashes, SHA-256, tokens).
  static final RegExp _hexHashPattern = RegExp(r'\b[0-9a-fA-F]{32,}\b');

  // Android / Unix / Windows local file system paths (preserves `package:` and `dart:`).
  static final RegExp _androidPathPattern = RegExp(
    r'(?:/data/(?:user/\d+|data)/[^\s:)]+|/storage/[^\s:)]+|/sdcard/[^\s:)]+|/Users/[^\s:)]+|/home/[^\s:)]+|[A-Za-z]:\\[^\s:)]+)',
  );

  // Phone numbers: explicit +country_code or wa.me numbers.
  static final RegExp _phonePattern = RegExp(
    r'(?:\+\d[\d\s()-]{7,16}\d|\b\d{9,15}\b)',
  );

  // ISO timestamp header (`--- [2026-10-19T...] [TAG] ---`).
  static final RegExp _isoTimestampHeader = RegExp(
    r'--- \[(\d{4}-\d{2}-\d{2}T[^\]]+)\] \[([^\]]+)\] ---',
  );

  // GPS lat/lng key-value pairs or decimal coordinates.
  static final RegExp _gpsPattern = RegExp(
    r'\b(?:lat|latitude|lng|lon|longitude)\s*[:=]\s*-?\d+\.\d+',
    caseSensitive: false,
  );

  // Currency / earnings figures (e.g. `1924.50 PLN`, `450 zł`, `netIncome: 2500`).
  static final RegExp _currencyPattern = RegExp(
    r'(?:\b\d+(?:[.,]\d+)?\s*(?:PLN\b|zł|zl\b)|\b(?:netIncome|cashReceived|fuelCost|rentalFee|netProfit)\s*[:=]\s*-?\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  );

  /// Sanitizes a single string (such as a log line or error message) by
  /// masking URLs, secrets, file paths, phone numbers, GPS, and PLN amounts.
  static String sanitizeText(String input) {
    if (input.isEmpty) return '';
    var out = input;
    out = out.replaceAll(_urlPattern, '[REDACTED_URL]');
    out = out.replaceAll(_emailPattern, '[REDACTED_EMAIL]');
    out = out.replaceAll(_telegramTokenPattern, '[REDACTED_SECRET]');
    out = out.replaceAllMapped(_bearerPattern, (m) {
      final prefix = m.group(1) ?? 'Bearer';
      return '$prefix [REDACTED_SECRET]';
    });
    out = out.replaceAllMapped(_secretKeyValPattern, (m) {
      final full = m.group(0) ?? '';
      final sepIdx = full.indexOf(RegExp(r'[:=]'));
      if (sepIdx < 0) return '[REDACTED_SECRET]';
      final prefix = full.substring(0, sepIdx + 1);
      return '$prefix [REDACTED_SECRET]';
    });
    out = out.replaceAll(_hexHashPattern, '[REDACTED_HASH]');
    out = out.replaceAll(_androidPathPattern, '[REDACTED_PATH]');
    out = out.replaceAll(_gpsPattern, '[REDACTED_LOCATION]');
    out = out.replaceAll(_currencyPattern, '[REDACTED_AMOUNT]');
    out = out.replaceAll(_phonePattern, '[REDACTED_PHONE]');
    return out;
  }

  /// Extracts at most the last [maxEntries] error blocks from [rawLog],
  /// sanitizes every line, and caps the output at [maxChars] characters.
  static String sanitizeCrashLogExcerpt(
    String rawLog, {
    int maxEntries = defaultMaxEntries,
    int maxChars = defaultMaxChars,
  }) {
    final trimmed = rawLog.trim();
    if (trimmed.isEmpty) return '';

    // Split on CrashLogger block headers `--- [timestamp] [TAG] ---`.
    final matches = _isoTimestampHeader.allMatches(trimmed).toList();
    List<String> blocks;
    if (matches.isEmpty) {
      blocks = <String>[trimmed];
    } else {
      blocks = <String>[];
      for (var i = 0; i < matches.length; i++) {
        final start = matches[i].start;
        final end = (i + 1 < matches.length)
            ? matches[i + 1].start
            : trimmed.length;
        blocks.add(trimmed.substring(start, end).trim());
      }
    }

    if (blocks.length > maxEntries) {
      blocks = blocks.sublist(blocks.length - maxEntries);
    }

    final sanitizedBlocks = <String>[];
    for (final block in blocks) {
      final lines = block.split('\n');
      final cleanLines = <String>[];
      for (final line in lines) {
        final headerMatch = _isoTimestampHeader.firstMatch(line);
        if (headerMatch != null) {
          // Preserve the timestamp and tag header intact, sanitize any rest.
          cleanLines.add(headerMatch.group(0)!);
        } else {
          cleanLines.add(sanitizeText(line));
        }
      }
      sanitizedBlocks.add(cleanLines.join('\n').trim());
    }

    var combined = sanitizedBlocks.join('\n\n').trim();
    if (combined.length > maxChars) {
      final bodyChars = maxChars > 4 ? maxChars - 4 : 0;
      combined = bodyChars == 0
          ? combined.substring(combined.length - maxChars)
          : '...\n${combined.substring(combined.length - bodyChars).trimLeft()}';
    }
    return combined;
  }
}

/// Builds the plain-text bug report shown in the live preview.
abstract final class BugReportFormatter {
  static String buildReportText({
    required BugCategory category,
    required String description,
    required bool includeDiagnostics,
    required BugReportDiagnostics? diagnostics,
    required bool includeCrashLogs,
    required String? rawCrashLog,
    BugScreenshotAttachment? screenshot,
    DateTime? reportedAt,
  }) {
    final ts = (reportedAt ?? DateTime.now()).toUtc().toIso8601String();
    final cleanDesc = description.trim();
    final buf = StringBuffer()
      ..writeln('=== RateHelper Bug Report ===')
      ..writeln('Category: ${category.label} (${category.name})')
      ..writeln('Reported At: $ts')
      ..writeln()
      ..writeln('--- Description ---')
      ..writeln(cleanDesc.isEmpty ? '-' : cleanDesc);

    buf.writeln();
    buf.writeln('--- Diagnostics ---');
    if (includeDiagnostics && diagnostics != null) {
      buf
        ..writeln('App Version: ${diagnostics.appVersion}')
        ..writeln('Device: ${diagnostics.deviceModel}')
        ..writeln('Android: ${diagnostics.androidVersion}')
        ..writeln('Language: ${diagnostics.language}')
        ..writeln('Overlay Orientation: ${diagnostics.pillOrientation}')
        ..writeln(
          'Overlay Cancel Button: ${diagnostics.showOverlayCancel ? "on" : "off"}',
        )
        ..writeln(
          'Notification Controls: ${diagnostics.notificationControls ? "on" : "off"}',
        )
        ..writeln(
          'Hide Pill (Shade-Only): ${diagnostics.hidePill ? "on" : "off"}',
        )
        ..writeln(
          'Steering Wheel Counter: ${diagnostics.steeringWheel ? "on" : "off"}',
        )
        ..writeln(
          'Auto-Complete Trips: ${diagnostics.autoComplete ? "on" : "off"}',
        )
        ..writeln('Keep Screen On: ${diagnostics.keepScreenOn ? "on" : "off"}');
    } else {
      buf.writeln('Excluded by user.');
    }

    if (includeCrashLogs) {
      buf.writeln();
      buf.writeln('--- Recent Error Logs (Sanitized) ---');
      final sanitized = BugReportSanitizer.sanitizeCrashLogExcerpt(
        rawCrashLog ?? '',
      );
      buf.writeln(sanitized.isEmpty ? 'No recent error entries.' : sanitized);
    }

    if (screenshot != null) {
      buf.writeln();
      buf.writeln('--- Attachment ---');
      buf.writeln('Screenshot: ${screenshot.name}');
    }

    return buf.toString().trimRight();
  }
}

typedef BugScreenshotPicker = Future<BugScreenshotPickResult> Function();
typedef BugCrashLogLoader = Future<String> Function();
typedef BugDiagnosticsLoader =
    Future<BugReportDiagnostics> Function(
      SettingsSnapshot snapshot,
      String? versionLabel,
    );
typedef BugReportSubmitter =
    Future<BugReportSubmitOutcome> Function(BugReportSubmission submission);

Future<BugReportDiagnostics> defaultLoadBugDiagnostics(
  SettingsSnapshot snapshot,
  String? versionLabel,
) async {
  var appVersion = (versionLabel != null && versionLabel.trim().isNotEmpty)
      ? versionLabel.trim()
      : '5.0.4';
  var deviceModel = 'Android Device';
  var androidVersion = 'Android';

  try {
    final native = await _kBugReportSysChannel
        .invokeMethod<Map<dynamic, dynamic>>('deviceDiagnostics');
    if (native != null) {
      final manufacturer = (native['manufacturer'] as String? ?? '').trim();
      final model = (native['model'] as String? ?? '').trim();
      if (manufacturer.isNotEmpty || model.isNotEmpty) {
        deviceModel = model.toLowerCase().startsWith(manufacturer.toLowerCase())
            ? model
            : '$manufacturer $model'.trim();
      }
      final rel = (native['androidRelease'] as String? ?? '').trim();
      final sdk = native['sdkInt'];
      if (rel.isNotEmpty && sdk is int && sdk > 0) {
        androidVersion = 'Android $rel (SDK $sdk)';
      } else if (rel.isNotEmpty) {
        androidVersion = 'Android $rel';
      }
      final nativeVer = (native['appVersion'] as String? ?? '').trim();
      final nativeBuild = (native['buildNumber'] as String? ?? '').trim();
      if (nativeVer.isNotEmpty) {
        appVersion = nativeBuild.isNotEmpty
            ? '$nativeVer+$nativeBuild'
            : nativeVer;
      }
    }
  } on MissingPluginException {
    // Fallback for tests or non-Android environments.
  } catch (_) {}

  if (!appVersion.contains('+')) {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        appVersion = info.buildNumber.isNotEmpty
            ? '${info.version}+${info.buildNumber}'
            : info.version;
      }
    } catch (_) {}
  }

  return BugReportDiagnostics(
    appVersion: appVersion,
    deviceModel: deviceModel,
    androidVersion: androidVersion,
    language: snapshot.lang.name,
    pillOrientation: snapshot.pillOrientation == PillOrientation.vertical
        ? 'vertical'
        : 'horizontal',
    showOverlayCancel: snapshot.showOverlayCancel,
    notificationControls: snapshot.notificationControls,
    hidePill: snapshot.hidePill,
    steeringWheel: snapshot.steeringWheel,
    autoComplete: snapshot.autoComplete,
    keepScreenOn: snapshot.keepScreenOn,
  );
}

Future<BugScreenshotPickResult> defaultPickBugScreenshot() async {
  try {
    final reply = await _kBugReportSysChannel
        .invokeMethod<Map<dynamic, dynamic>>('pickBugScreenshot');
    if (reply == null) return const BugScreenshotPickResult.cancelled();
    final status = reply['status'] as String? ?? 'failed';
    if (status == 'cancelled') return const BugScreenshotPickResult.cancelled();
    if (status == 'too_large') return const BugScreenshotPickResult.tooLarge();
    final path = reply['path'] as String?;
    final name = reply['name'] as String? ?? 'screenshot.png';
    final rawMime = (reply['mimeType'] as String? ?? 'image/png').toLowerCase();
    final mime = rawMime == 'image/jpg' ? 'image/jpeg' : rawMime;
    if (status == 'ok' && path != null && path.isNotEmpty) {
      return BugScreenshotPickResult.ok(
        BugScreenshotAttachment(path: path, name: name, mimeType: mime),
      );
    }
    return const BugScreenshotPickResult.failed();
  } on MissingPluginException {
    return const BugScreenshotPickResult.failed();
  } catch (_) {
    return const BugScreenshotPickResult.failed();
  }
}

Future<String> defaultLoadCrashLog() async {
  try {
    final file = await CrashLogger.currentLogFile();
    if (file == null) return '';
    return await file.readAsString();
  } catch (_) {
    return '';
  }
}

Future<BugReportSubmitOutcome> defaultSubmitBugReport(
  BugReportSubmission submission,
) async {
  final api = BugReportApi.fromEnvironment();
  if (api == null) return BugReportSubmitOutcome.unavailable;
  return api.submit(submission);
}

/// Opens the modal bottom sheet for creating, previewing, and sending a
/// sanitized bug report after an explicit user action.
Future<void> showBugReportSheet(
  BuildContext context, {
  required SettingsSnapshot snapshot,
  String? versionLabel,
  BugScreenshotPicker? pickScreenshot,
  BugCrashLogLoader? loadCrashLog,
  BugDiagnosticsLoader? loadDiagnostics,
  BugReportSubmitter? submitReport,
  DateTime? now,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.dialog,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _BugReportSheet(
      snapshot: snapshot,
      versionLabel: versionLabel,
      pickScreenshot: pickScreenshot ?? defaultPickBugScreenshot,
      loadCrashLog: loadCrashLog ?? defaultLoadCrashLog,
      loadDiagnostics: loadDiagnostics ?? defaultLoadBugDiagnostics,
      submitReport: submitReport ?? defaultSubmitBugReport,
      reportedAt: now,
    ),
  );
}

class _BugReportSheet extends StatefulWidget {
  const _BugReportSheet({
    required this.snapshot,
    required this.versionLabel,
    required this.pickScreenshot,
    required this.loadCrashLog,
    required this.loadDiagnostics,
    required this.submitReport,
    this.reportedAt,
  });

  final SettingsSnapshot snapshot;
  final String? versionLabel;
  final BugScreenshotPicker pickScreenshot;
  final BugCrashLogLoader loadCrashLog;
  final BugDiagnosticsLoader loadDiagnostics;
  final BugReportSubmitter submitReport;
  final DateTime? reportedAt;

  @override
  State<_BugReportSheet> createState() => _BugReportSheetState();
}

class _BugReportSheetState extends State<_BugReportSheet> {
  final TextEditingController _descriptionCtrl = TextEditingController();
  late final DateTime _reportedAt = widget.reportedAt ?? DateTime.now();

  BugCategory _category = BugCategory.overlay;
  bool _includeDiagnostics = true;
  bool _includeCrashLogs = false; // Mandatory: OFF by default for privacy
  BugReportDiagnostics? _diagnostics;
  String? _rawCrashLog;
  BugScreenshotAttachment? _screenshot;
  String? _inlineError;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _diagnostics = BugReportDiagnostics(
      appVersion: widget.versionLabel ?? '5.0.4',
      deviceModel: 'Android Device',
      androidVersion: 'Android',
      language: widget.snapshot.lang.name,
      pillOrientation:
          widget.snapshot.pillOrientation == PillOrientation.vertical
          ? 'vertical'
          : 'horizontal',
      showOverlayCancel: widget.snapshot.showOverlayCancel,
      notificationControls: widget.snapshot.notificationControls,
      hidePill: widget.snapshot.hidePill,
      steeringWheel: widget.snapshot.steeringWheel,
      autoComplete: widget.snapshot.autoComplete,
      keepScreenOn: widget.snapshot.keepScreenOn,
    );
    _descriptionCtrl.addListener(_onDescriptionChanged);
    unawaited(_refreshDiagnostics());
  }

  @override
  void dispose() {
    _descriptionCtrl.removeListener(_onDescriptionChanged);
    _descriptionCtrl.dispose();
    super.dispose();
  }

  void _onDescriptionChanged() {
    if (!mounted) return;
    setState(() {
      if (_inlineError != null && _descriptionCtrl.text.trim().isNotEmpty) {
        _inlineError = null;
      }
    });
  }

  Future<void> _refreshDiagnostics() async {
    try {
      final loaded = await widget.loadDiagnostics(
        widget.snapshot,
        widget.versionLabel,
      );
      if (!mounted) return;
      setState(() => _diagnostics = loaded);
    } catch (_) {}
  }

  Future<void> _toggleCrashLogs(bool enabled) async {
    setState(() {
      _includeCrashLogs = enabled;
    });
    if (enabled && _rawCrashLog == null) {
      final loaded = await widget.loadCrashLog();
      if (!mounted) return;
      setState(() {
        _rawCrashLog = loaded;
      });
    }
  }

  Future<void> _handlePickScreenshot() async {
    final res = await widget.pickScreenshot();
    if (!mounted) return;
    if (res.status == 'cancelled') return;
    if (res.status == 'too_large') {
      setState(() => _inlineError = S.reportScreenshotTooLarge);
      return;
    }
    if (res.status == 'ok' && res.attachment != null) {
      setState(() {
        _screenshot = res.attachment;
        _inlineError = null;
      });
      return;
    }
    setState(() => _inlineError = S.reportScreenshotFailed);
  }

  String _buildCurrentReportText() {
    return BugReportFormatter.buildReportText(
      category: _category,
      description: _descriptionCtrl.text,
      includeDiagnostics: _includeDiagnostics,
      diagnostics: _diagnostics,
      includeCrashLogs: _includeCrashLogs,
      rawCrashLog: _rawCrashLog,
      screenshot: _screenshot,
      reportedAt: _reportedAt,
    );
  }

  Future<void> _handleSend() async {
    if (_sending) return;
    if (_descriptionCtrl.text.trim().isEmpty) {
      setState(() => _inlineError = S.reportDescriptionEmptyError);
      return;
    }
    setState(() {
      _inlineError = null;
      _sending = true;
    });
    try {
      final status = await widget.submitReport(
        BugReportSubmission(
          category: _category.name,
          description: _descriptionCtrl.text.trim(),
          reportedAt: _reportedAt,
          diagnostics: _includeDiagnostics ? _diagnostics : null,
          crashLog: _includeCrashLogs
              ? BugReportSanitizer.sanitizeCrashLogExcerpt(_rawCrashLog ?? '')
              : null,
          screenshot: _screenshot,
        ),
      );
      if (!mounted) return;
      if (status == BugReportSubmitOutcome.sent) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(S.reportSendSuccess)));
        return;
      }
      setState(() {
        _inlineError = switch (status) {
          BugReportSubmitOutcome.invalid => S.reportSendInvalid,
          BugReportSubmitOutcome.tooLarge => S.reportScreenshotTooLarge,
          BugReportSubmitOutcome.rateLimited => S.reportSendRateLimited,
          BugReportSubmitOutcome.duplicate => S.reportSendDuplicate,
          BugReportSubmitOutcome.unavailable => S.reportSendUnavailable,
          BugReportSubmitOutcome.failed => S.reportSendFailed,
          BugReportSubmitOutcome.sent => null,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _inlineError = S.reportSendFailed);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final previewText = _buildCurrentReportText();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.rate_review_outlined,
                        color: AppColors.emerald,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          S.reportProblem,
                          style: const TextStyle(
                            fontFamily: AppFonts.dmSans,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('bug-report-close'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.hairline),
                Expanded(
                  child: ListView(
                    key: const ValueKey('bug-report-scroll'),
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: [
                      // 1. Category selector
                      Text(
                        S.reportCategoryEyebrow,
                        style: AppTextStyles.eyebrowStyle(
                          AppColors.labelText,
                        ).copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final cat in BugCategory.values)
                            _CategoryChip(
                              key: ValueKey('bug-category-${cat.name}'),
                              label: cat.label,
                              selected: _category == cat,
                              onTap: () => setState(() => _category = cat),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // 2. Problem description
                      Text(
                        S.reportDescriptionEyebrow,
                        style: AppTextStyles.eyebrowStyle(
                          AppColors.labelText,
                        ).copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('bug-report-description'),
                        controller: _descriptionCtrl,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 1000,
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 14,
                          color: Colors.white,
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          hintText: S.reportDescriptionHint,
                          hintStyle: const TextStyle(
                            fontFamily: AppFonts.dmSans,
                            fontSize: 13.5,
                            color: AppColors.mutedText,
                          ),
                          filled: true,
                          fillColor: AppColors.card,
                          counterStyle: const TextStyle(
                            fontFamily: AppFonts.dmSans,
                            fontSize: 11,
                            color: AppColors.mutedText,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                          enabledBorder: const OutlineInputBorder(
                            borderRadius: AppRadius.mdBorder,
                            borderSide: BorderSide(color: AppColors.hairline),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: AppRadius.mdBorder,
                            borderSide: BorderSide(
                              color: AppColors.emerald,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      if (_inlineError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _inlineError!,
                          key: const ValueKey('bug-report-error'),
                          style: const TextStyle(
                            fontFamily: AppFonts.dmSans,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.crimson,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),

                      // 3. Optional screenshot attachment
                      Text(
                        S.reportScreenshotEyebrow,
                        style: AppTextStyles.eyebrowStyle(
                          AppColors.labelText,
                        ).copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      if (_screenshot == null)
                        OutlinedButton.icon(
                          key: const ValueKey('bug-report-attach-screenshot'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(kMinTouchTarget),
                            foregroundColor: Colors.white,
                            side: const BorderSide(
                              color: AppColors.strongBorder,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.mdBorder,
                            ),
                          ),
                          onPressed: _handlePickScreenshot,
                          icon: const Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 20,
                            color: AppColors.emerald,
                          ),
                          label: Text(
                            S.reportAttachScreenshot,
                            style: const TextStyle(
                              fontFamily: AppFonts.dmSans,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        Container(
                          key: const ValueKey('bug-report-screenshot-card'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: AppRadius.mdBorder,
                            border: Border.all(
                              color: AppColors.emerald.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.image_outlined,
                                color: AppColors.emerald,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _screenshot!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: AppFonts.dmSans,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              TextButton(
                                key: const ValueKey(
                                  'bug-report-remove-screenshot',
                                ),
                                onPressed: () =>
                                    setState(() => _screenshot = null),
                                child: Text(
                                  S.reportRemoveScreenshot,
                                  style: const TextStyle(
                                    fontFamily: AppFonts.dmSans,
                                    color: AppColors.crimson,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),

                      // 4. Diagnostics & crash logs toggles
                      Text(
                        S.reportOptionsEyebrow,
                        style: AppTextStyles.eyebrowStyle(
                          AppColors.labelText,
                        ).copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: AppRadius.mdBorder,
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Column(
                          children: [
                            _OptionSwitchTile(
                              switchKey: const ValueKey(
                                'bug-report-diagnostics-switch',
                              ),
                              title: S.reportIncludeDiagnostics,
                              subtitle: S.reportIncludeDiagnosticsSub,
                              value: _includeDiagnostics,
                              onChanged: (val) =>
                                  setState(() => _includeDiagnostics = val),
                            ),
                            const Divider(height: 1, color: AppColors.hairline),
                            _OptionSwitchTile(
                              switchKey: const ValueKey(
                                'bug-report-crash-logs-switch',
                              ),
                              title: S.reportIncludeCrashLogs,
                              subtitle: S.reportIncludeCrashLogsSub,
                              value: _includeCrashLogs,
                              onChanged: (val) =>
                                  unawaited(_toggleCrashLogs(val)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 5. Full live preview before sending
                      Text(
                        S.reportPreviewEyebrow,
                        style: AppTextStyles.eyebrowStyle(
                          AppColors.labelText,
                        ).copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: AppRadius.mdBorder,
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: SelectableText(
                          previewText,
                          key: const ValueKey('bug-report-preview-text'),
                          style: const TextStyle(
                            fontFamily: AppFonts.jetBrainsMono,
                            fontSize: 11.5,
                            color: Colors.white70,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.send_outlined,
                            color: AppColors.emerald,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              S.reportDeliveryNotice,
                              style: const TextStyle(
                                fontFamily: AppFonts.dmSans,
                                fontSize: 12,
                                color: AppColors.mutedText,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            color: AppColors.emerald,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              S.reportPrivacyNotice,
                              style: const TextStyle(
                                fontFamily: AppFonts.dmSans,
                                fontSize: 12,
                                color: AppColors.mutedText,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.hairline),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: kMinTouchTarget,
                    child: FilledButton.icon(
                      key: const ValueKey('bug-report-send-button'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.black,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.mdBorder,
                        ),
                      ),
                      onPressed: _sending ? null : _handleSend,
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _sending ? S.reportSending : S.reportSendAction,
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
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
          ? AppColors.emerald.withValues(alpha: 0.16)
          : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        side: BorderSide(
          color: selected ? AppColors.emerald : AppColors.hairline,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? AppColors.emerald : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionSwitchTile extends StatelessWidget {
  const _OptionSwitchTile({
    required this.switchKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: 12,
                      color: AppColors.mutedText,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              key: switchKey,
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.emerald,
              activeTrackColor: AppColors.emerald.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}
