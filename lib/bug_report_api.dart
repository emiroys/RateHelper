import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

const int maxBugScreenshotBytes = 5 * 1024 * 1024;

enum BugReportSubmitOutcome {
  sent,
  invalid,
  tooLarge,
  rateLimited,
  duplicate,
  unavailable,
  failed,
}

@immutable
class BugReportDiagnostics {
  const BugReportDiagnostics({
    required this.appVersion,
    required this.deviceModel,
    required this.androidVersion,
    required this.language,
    required this.pillOrientation,
    required this.showOverlayCancel,
    required this.notificationControls,
    required this.hidePill,
    required this.steeringWheel,
    required this.autoComplete,
    required this.keepScreenOn,
  });

  final String appVersion;
  final String deviceModel;
  final String androidVersion;
  final String language;
  final String pillOrientation;
  final bool showOverlayCancel;
  final bool notificationControls;
  final bool hidePill;
  final bool steeringWheel;
  final bool autoComplete;
  final bool keepScreenOn;

  Map<String, Object> toJson() => {
    'appVersion': appVersion,
    'deviceModel': deviceModel,
    'androidVersion': androidVersion,
    'language': language,
    'pillOrientation': pillOrientation,
    'showOverlayCancel': showOverlayCancel,
    'notificationControls': notificationControls,
    'hidePill': hidePill,
    'steeringWheel': steeringWheel,
    'autoComplete': autoComplete,
    'keepScreenOn': keepScreenOn,
  };
}

@immutable
class BugScreenshotAttachment {
  const BugScreenshotAttachment({
    required this.path,
    required this.name,
    this.mimeType = 'image/png',
  });

  final String path;
  final String name;
  final String mimeType;
}

@immutable
class BugReportSubmission {
  const BugReportSubmission({
    required this.category,
    required this.description,
    required this.reportedAt,
    this.diagnostics,
    this.crashLog,
    this.screenshot,
  });

  final String category;
  final String description;
  final DateTime reportedAt;
  final BugReportDiagnostics? diagnostics;
  final String? crashLog;
  final BugScreenshotAttachment? screenshot;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'category': category,
    'description': description.trim(),
    'reportedAt': reportedAt.toUtc().toIso8601String(),
    'diagnostics': diagnostics?.toJson(),
    'crashLog': crashLog,
  };
}

abstract class BugReportApi {
  Future<BugReportSubmitOutcome> submit(BugReportSubmission submission);

  /// Uses the same HTTPS Worker base as the fuel-price API. The URL remains a
  /// compile-time value; Telegram credentials never enter the application.
  static BugReportApi? fromEnvironment() =>
      fromConfig(const String.fromEnvironment('ORLEN_API_URL'));

  @visibleForTesting
  static BugReportApi? fromConfig(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == 'mock') return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) return null;
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return HttpBugReportApi(uri.replace(path: path));
  }
}

class HttpBugReportApi implements BugReportApi {
  HttpBugReportApi(this.baseUrl, {HttpClient Function()? newClient})
    : _newClient = newClient ?? HttpClient.new;

  final Uri baseUrl;
  final HttpClient Function() _newClient;

  static const Duration _timeout = Duration(seconds: 15);
  static const int _maxResponseBytes = 16 * 1024;

  Uri get _endpoint => baseUrl.replace(path: '${baseUrl.path}/bug-report');

  @override
  Future<BugReportSubmitOutcome> submit(BugReportSubmission submission) async {
    final description = submission.description.trim();
    if (description.isEmpty || description.length > 1000) {
      return BugReportSubmitOutcome.invalid;
    }

    List<int>? screenshotBytes;
    final screenshot = submission.screenshot;
    if (screenshot != null) {
      if (!_allowedMimeTypes.contains(screenshot.mimeType.toLowerCase())) {
        return BugReportSubmitOutcome.invalid;
      }
      try {
        final file = File(screenshot.path);
        final length = await file.length();
        if (length > maxBugScreenshotBytes) {
          return BugReportSubmitOutcome.tooLarge;
        }
        screenshotBytes = await file.readAsBytes();
        if (!_hasExpectedSignature(screenshot.mimeType, screenshotBytes)) {
          return BugReportSubmitOutcome.invalid;
        }
      } catch (_) {
        return BugReportSubmitOutcome.failed;
      }
    }

    final payloadBytes = utf8.encode(jsonEncode(submission.toJson()));
    final boundary =
        'ratehelper-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final parts = _multipartParts(
      boundary: boundary,
      payload: payloadBytes,
      screenshot: screenshot,
      screenshotBytes: screenshotBytes,
    );
    final contentLength = parts.fold<int>(0, (sum, part) => sum + part.length);

    final client = _newClient()
      ..connectionTimeout = _timeout
      ..userAgent = 'RateHelper';
    try {
      final request = await client.postUrl(_endpoint).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );
      request.contentLength = contentLength;
      for (final part in parts) {
        request.add(part);
      }
      final response = await request.close().timeout(_timeout);
      await _drainResponse(response);
      return switch (response.statusCode) {
        HttpStatus.created || HttpStatus.ok => BugReportSubmitOutcome.sent,
        HttpStatus.badRequest ||
        HttpStatus.unprocessableEntity => BugReportSubmitOutcome.invalid,
        HttpStatus.requestEntityTooLarge => BugReportSubmitOutcome.tooLarge,
        HttpStatus.tooManyRequests => BugReportSubmitOutcome.rateLimited,
        HttpStatus.conflict => BugReportSubmitOutcome.duplicate,
        HttpStatus.serviceUnavailable => BugReportSubmitOutcome.unavailable,
        _ => BugReportSubmitOutcome.failed,
      };
    } catch (_) {
      return BugReportSubmitOutcome.failed;
    } finally {
      client.close(force: true);
    }
  }

  static const Set<String> _allowedMimeTypes = {'image/png', 'image/jpeg'};

  static bool _hasExpectedSignature(String mimeType, List<int> bytes) {
    final mime = mimeType.toLowerCase();
    if (mime == 'image/png') {
      const sig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
      return bytes.length >= sig.length && listEquals(bytes.sublist(0, 8), sig);
    }
    return bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
  }

  static List<List<int>> _multipartParts({
    required String boundary,
    required List<int> payload,
    required BugScreenshotAttachment? screenshot,
    required List<int>? screenshotBytes,
  }) {
    final parts = <List<int>>[
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="payload"\r\n'
        'Content-Type: application/json; charset=utf-8\r\n\r\n',
      ),
      payload,
      utf8.encode('\r\n'),
    ];
    if (screenshot != null && screenshotBytes != null) {
      final mime = screenshot.mimeType.toLowerCase();
      final extension = mime == 'image/png' ? 'png' : 'jpg';
      parts
        ..add(
          utf8.encode(
            '--$boundary\r\n'
            'Content-Disposition: form-data; name="screenshot"; '
            'filename="screenshot.$extension"\r\n'
            'Content-Type: $mime\r\n\r\n',
          ),
        )
        ..add(screenshotBytes)
        ..add(utf8.encode('\r\n'));
    }
    parts.add(utf8.encode('--$boundary--\r\n'));
    return parts;
  }

  static Future<void> _drainResponse(HttpClientResponse response) async {
    var read = 0;
    await for (final chunk in response.timeout(_timeout)) {
      read += chunk.length;
      if (read > _maxResponseBytes) {
        throw const HttpException('Response too large');
      }
    }
  }
}
