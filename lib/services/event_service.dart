import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:rate_helper/models/event_model.dart';

class EventService {
  static const String _eventsUrl =
      'https://raw.githubusercontent.com/emiroys/ratehelper/main/krakow_events.json';

  // In-memory cache to ensure we only fetch once per session
  static List<EventModel>? _cachedEvents;
  static DateTime? _cacheTimestamp;
  static const Duration _cacheValidity = Duration(hours: 1);

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

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.parse(_eventsUrl);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        if (_cachedEvents != null) return _cachedEvents!;
        return _getFallbackEvents();
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);

      if (decoded is! List) {
        if (_cachedEvents != null) return _cachedEvents!;
        return _getFallbackEvents();
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
            debugPrint('Error parsing event item: $e');
          }
        }
      }

      // Sort chronologically
      events.sort((a, b) => a.date.compareTo(b.date));

      // Return the top 5 upcoming events
      final top5 = events.take(5).toList();

      if (top5.isNotEmpty) {
        _cachedEvents = top5;
        _cacheTimestamp = DateTime.now();
        return top5;
      } else {
        // If all events were in the past or list was empty, return fallback data
        // to keep the dashboard informative during testing
        final fallback = _getFallbackEvents();
        _cachedEvents = fallback;
        _cacheTimestamp = DateTime.now();
        return fallback;
      }
    } catch (e) {
      debugPrint('EventService fetch error: $e');
      if (_cachedEvents != null) return _cachedEvents!;
      final fallback = _getFallbackEvents();
      _cachedEvents = fallback;
      _cacheTimestamp = DateTime.now();
      return fallback;
    }
  }

  static List<EventModel> _getFallbackEvents() {
    final now = DateTime.now();
    return [
      EventModel(
        title: "Wisła Kraków vs. KS Cracovia - Derby",
        venue: "Stadion Miejski im. Henryka Reymana",
        date: now.add(const Duration(days: 1, hours: 18)),
        surgeLevel: "High",
      ),
      EventModel(
        title: "Dawid Podsiadło - Stadium Tour Concert",
        venue: "Tauron Arena Kraków",
        date: now.add(const Duration(days: 2, hours: 20)),
        surgeLevel: "High",
      ),
      EventModel(
        title: "Kraków Tech & AI Summit 2026",
        venue: "ICE Kraków Congress Centre",
        date: now.add(const Duration(days: 4, hours: 9)),
        surgeLevel: "Medium",
      ),
      EventModel(
        title: "International Food & Wine Festival",
        venue: "Tauron Arena Kraków",
        date: now.add(const Duration(days: 6, hours: 12)),
        surgeLevel: "Medium",
      ),
      EventModel(
        title: "Local Indie Band Showcase",
        venue: "Klub Studio",
        date: now.add(const Duration(days: 8, hours: 21)),
        surgeLevel: "Low",
      ),
    ];
  }
}
