import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Result of one POST /survey attempt.
enum SurveySubmitOutcome {
  /// The Worker stored a new response.
  sent,

  /// This installation id was already stored.
  duplicate,

  /// Network, timeout, rate-limit or server failure; safe to retry later.
  retryable,

  /// The Worker rejected the schema/values. Keeping the pending answer is
  /// still safer than locking the driver out of the app.
  invalid,
}

abstract class SurveyApi {
  Future<SurveySubmitOutcome> submit(Map<String, Object?> payload);

  /// Uses the same HTTPS Worker base as the fuel-price and bug-report clients.
  static SurveyApi? fromEnvironment() =>
      fromConfig(const String.fromEnvironment('ORLEN_API_URL'));

  @visibleForTesting
  static SurveyApi? fromConfig(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == 'mock') return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) return null;
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return HttpSurveyApi(uri.replace(path: path));
  }
}

class HttpSurveyApi implements SurveyApi {
  HttpSurveyApi(this.baseUrl, {HttpClient Function()? newClient})
    : _newClient = newClient ?? HttpClient.new;

  final Uri baseUrl;
  final HttpClient Function() _newClient;

  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxResponseBytes = 4096;

  Uri get _endpoint => baseUrl.replace(path: '${baseUrl.path}/survey');

  @override
  Future<SurveySubmitOutcome> submit(Map<String, Object?> payload) async {
    final client = _newClient()
      ..connectionTimeout = _timeout
      ..userAgent = 'RateHelper';
    try {
      final request = await client.postUrl(_endpoint).timeout(_timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(_timeout);
      await _drainResponse(response);
      return switch (response.statusCode) {
        HttpStatus.ok ||
        HttpStatus.created ||
        HttpStatus.accepted => SurveySubmitOutcome.sent,
        HttpStatus.conflict => SurveySubmitOutcome.duplicate,
        HttpStatus.badRequest ||
        HttpStatus.requestEntityTooLarge ||
        HttpStatus.unsupportedMediaType ||
        HttpStatus.unprocessableEntity => SurveySubmitOutcome.invalid,
        _ => SurveySubmitOutcome.retryable,
      };
    } catch (_) {
      return SurveySubmitOutcome.retryable;
    } finally {
      client.close(force: true);
    }
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
