import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:rate_helper/models/event_model.dart';
import 'package:rate_helper/log.dart';

class EventService {
  static const String _eventsUrl =
      'https://raw.githubusercontent.com/emiroys/ratehelper/main/krakow_events.json';

  // In-memory cache to ensure we only fetch once per session
  static List<EventModel>? _cachedEvents;
  static DateTime? _cacheTimestamp;
  static const Duration _cacheValidity = Duration(hours: 1);

  static Future<List<EventModel>>? _inFlight;

  static void clearCache() {
    _cachedEvents = null;
    _cacheTimestamp = null;
  }

  static Future<List<EventModel>> fetchUpcomingEvents({
    bool forceRefresh = false,
  }) async {
    // Return cached events if available and valid within session
    if (!forceRefresh && _cachedEvents != null && _cacheTimestamp != null) {
      if (DateTime.now().difference(_cacheTimestamp!) < _cacheValidity) {
        return _cachedEvents!;
      }
    }

    if (_inFlight != null) return _inFlight!;

    _inFlight = _fetchWithRetry();
    try {
      final result = await _inFlight!;
      return result;
    } finally {
      _inFlight = null;
    }
  }

  static Future<List<EventModel>> _fetchWithRetry() async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      try {
        return await _fetchOnce();
      } catch (e, s) {
        lastError = e;
        lastStack = s;
      }
    }

    loge('EventService fetch failed', name: 'events', error: lastError, stack: lastStack);
    // Stale real data beats fresh fake data; no cache -> propagate the
    // failure so RadarScreen's error state (with retry) finally renders.
    if (_cachedEvents != null) return _cachedEvents!;
    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  static Future<List<EventModel>> _fetchOnce() async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.parse(_eventsUrl);
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      
      final response = await request.close().timeout(const Duration(seconds: 10));

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(body);

      if (decoded is! List) {
        throw const FormatException('Expected JSON array');
      }

      final now = DateTime.now();
      final List<EventModel> events = [];

      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            final event = EventModel.fromJson(item);
            // Filter out past events (allow events within the last 2 hours to stay visible)
            if (event.date.isAfter(now.subtract(const Duration(hours: 2)))) {
              events.add(event);
            }
          } catch (e) {
            // Debug-only: a single malformed item is non-fatal and must not
            // spam release logcat once per item on every 30-min refetch.
            logd('Error parsing event item: $e', name: 'events');
          }
        }
      }

      // Sort chronologically
      events.sort((a, b) => a.date.compareTo(b.date));

      // Return the top 5 upcoming events
      final top5 = events.take(5).toList();

      _cachedEvents = top5;
      _cacheTimestamp = DateTime.now();
      return top5;
    } finally {
      client.close(force: true);
    }
  }
}
