import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../log.dart';
import 'fuel_prices.dart';
import 'orlen_stations.dart';

/// Result of a crowd-sourced price submission. [pending] means the Worker
/// queued it and the admin got the Telegram approve/reject message; nothing
/// is public until the admin approves.
enum SubmitOutcome { pending, invalid, rateLimited, failed }

@immutable
class PriceSubmission {
  const PriceSubmission({
    required this.stationId,
    required this.fuel,
    required this.price,
  });

  final String stationId;
  final FuelType fuel;
  final double price;

  Map<String, Object> toJson() => {
    'stationId': stationId,
    'fuel': fuel.wireName,
    'price': price,
  };
}

/// Contract with `backend/orlen-worker` (see its README):
/// `GET {base}/prices` → `{"stations": {id: {pb95|lpg: {price, updatedAt}}}}`,
/// `POST {base}/submissions` with [PriceSubmission.toJson] → 202 when queued.
abstract class FuelPriceApi {
  Future<PriceBook> fetchPrices();

  Future<SubmitOutcome> submit(PriceSubmission submission);

  /// Built from `--dart-define=ORLEN_API_URL=...`. Null when unset or not an
  /// https URL, so public builds never open a socket for this feature.
  /// The literal value `mock` gives a developer an in-memory backend that
  /// publishes submissions immediately.
  static FuelPriceApi? fromEnvironment() =>
      fromConfig(const String.fromEnvironment('ORLEN_API_URL'));

  static FuelPriceApi? fromConfig(String raw) {
    final value = raw.trim();
    if (value == 'mock') return MockFuelPriceApi();
    final base = parseBaseUrl(value);
    return base == null ? null : HttpFuelPriceApi(base);
  }

  static Uri? parseBaseUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) return null;
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.replace(path: path);
  }
}

class HttpFuelPriceApi implements FuelPriceApi {
  HttpFuelPriceApi(this.baseUrl, {HttpClient Function()? newClient})
    : _newClient = newClient ?? HttpClient.new;

  final Uri baseUrl;
  final HttpClient Function() _newClient;

  static const Duration _timeout = Duration(seconds: 10);

  /// The prices document is tiny; anything bigger is not ours.
  static const int _maxBodyBytes = 256 * 1024;

  Uri _endpoint(String name) => baseUrl.replace(path: '${baseUrl.path}/$name');

  @override
  Future<PriceBook> fetchPrices() async {
    final client = _open();
    try {
      final request = await client
          .getUrl(_endpoint('prices'))
          .timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      final body = await _readBody(response);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return parsePriceBook(jsonDecode(body));
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<SubmitOutcome> submit(PriceSubmission submission) async {
    final client = _open();
    try {
      final request = await client
          .postUrl(_endpoint('submissions'))
          .timeout(_timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode(submission.toJson()));
      final response = await request.close().timeout(_timeout);
      await _readBody(response);
      return switch (response.statusCode) {
        HttpStatus.accepted || HttpStatus.ok => SubmitOutcome.pending,
        HttpStatus.badRequest ||
        HttpStatus.unprocessableEntity => SubmitOutcome.invalid,
        HttpStatus.tooManyRequests => SubmitOutcome.rateLimited,
        _ => SubmitOutcome.failed,
      };
    } catch (e, s) {
      loge('fuel price submit failed', name: 'fuel', error: e, stack: s);
      return SubmitOutcome.failed;
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _open() => _newClient()
    ..connectionTimeout = _timeout
    ..userAgent = 'RateHelper';

  Future<String> _readBody(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(_timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBodyBytes) {
        throw const HttpException('Response too large');
      }
    }
    return utf8.decode(bytes);
  }
}

/// `ORLEN_API_URL=mock`: no network, submissions publish at once so the
/// whole screen can be tried without the Worker.
class MockFuelPriceApi implements FuelPriceApi {
  MockFuelPriceApi({PriceBook? initial, DateTime Function()? now})
    : _book = {...?initial},
      _now = now ?? DateTime.now;

  final PriceBook _book;
  final DateTime Function() _now;

  @override
  Future<PriceBook> fetchPrices() async => Map.of(_book);

  @override
  Future<SubmitOutcome> submit(PriceSubmission submission) async {
    final station = stationById(submission.stationId);
    if (station == null ||
        !station.sells(submission.fuel) ||
        !isPriceInRange(submission.fuel, submission.price)) {
      return SubmitOutcome.invalid;
    }
    final price = FuelPrice(price: submission.price, updatedAt: _now());
    final current = _book[submission.stationId] ?? StationPrices.empty;
    _book[submission.stationId] = switch (submission.fuel) {
      FuelType.pb95 => StationPrices(pb95: price, lpg: current.lpg),
      FuelType.lpg => StationPrices(pb95: current.pb95, lpg: price),
    };
    return SubmitOutcome.pending;
  }
}

@immutable
class CachedPrices {
  const CachedPrices(this.book, this.fetchedAt);

  final PriceBook book;
  final DateTime fetchedAt;
}

/// Last successful `/prices` response, so the screen opens with numbers
/// even offline.
abstract final class FuelPriceCache {
  static const jsonKey = 'fuel_prices_cache_json';
  static const atKey = 'fuel_prices_cache_at_ms';

  static Future<CachedPrices?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(jsonKey);
      final ms = prefs.getInt(atKey);
      if (raw == null || ms == null || ms <= 0) return null;
      return CachedPrices(
        parsePriceBook(jsonDecode(raw)),
        DateTime.fromMillisecondsSinceEpoch(ms),
      );
    } catch (e, s) {
      loge('fuel cache unreadable', name: 'fuel', error: e, stack: s);
      return null;
    }
  }

  static Future<void> write(PriceBook book, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(jsonKey, jsonEncode(encodePriceBook(book)));
      await prefs.setInt(atKey, at.millisecondsSinceEpoch);
    } catch (e, s) {
      loge('fuel cache write failed', name: 'fuel', error: e, stack: s);
    }
  }
}
