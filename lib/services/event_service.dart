import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/log.dart';
import 'package:rate_helper/models/event_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'github_access.dart';
import 'github_http.dart';

/// What the radar is allowed to draw after a load.
///
/// [events] is null when nothing has been fetched and there is no cache.
/// An empty list means a fetch succeeded and nothing upcoming remained.
class EventFetchResult {
  const EventFetchResult({this.events, this.fetchedAt, this.error});

  const EventFetchResult.notLoaded()
      : events = null,
        fetchedAt = null,
        error = null;

  final List<EventModel>? events;
  final DateTime? fetchedAt;
  final Object? error;

  bool get loaded => events != null;
}

class EventService {
  static const String _eventsUrl =
      'https://raw.githubusercontent.com/emiroys/ratehelper/main/krakow_events.json';

  /// Display strings from the remote file are untrusted. Cap them so one
  /// oversized field cannot blow the radar card.
  static const int maxTitleChars = 120;
  static const int maxVenueChars = 120;
  static const int maxSurgeChars = 16;

  /// Dates further than this from [DateTime.now] are rejected, not shown.
  static const Duration maxDateSkew = Duration(days: 365);

  /// Persisted so a later launch can show the last list and its age without
  /// opening a socket when automatic fetch is off.
  static const eventsCacheJsonKey = 'events_cache_json';
  static const eventsCacheAtKey = 'events_cache_at_ms';

  // In-memory cache so a fresh list is not re-read from disk on every frame.
  static List<EventModel>? _cachedEvents;
  static DateTime? _cacheTimestamp;
  static const Duration _cacheValidity = Duration(hours: 1);

  static void clearCache() {
    _cachedEvents = null;
    _cacheTimestamp = null;
  }

  /// [allowNetwork] false never opens a socket: a stored list is returned as-is,
  /// and a missing list comes back as [EventFetchResult.notLoaded].
  /// [forceRefresh] skips the one-hour freshness window. The caller sets it
  /// only after the driver taps refresh or Load events.
  static Future<EventFetchResult> load({
    required bool allowNetwork,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final fresh = _freshMemory();
      if (fresh != null) return fresh;
    }

    final stored = await _readStored();
    if (!allowNetwork) {
      if (stored != null) {
        _remember(stored.events!, stored.fetchedAt!);
        return stored;
      }
      final memory = _memoryResult();
      if (memory != null) return memory;
      return const EventFetchResult.notLoaded();
    }

    if (!forceRefresh && stored != null && _isFresh(stored.fetchedAt)) {
      _remember(stored.events!, stored.fetchedAt!);
      return stored;
    }

    try {
      final events = await _fetchWithRetry();
      final at = _cacheTimestamp ?? DateTime.now();
      final result = EventFetchResult(events: events, fetchedAt: at);
      await _writeStored(result);
      return result;
    } catch (e) {
      if (stored != null) return stored;
      final memory = _memoryResult();
      if (memory != null) return memory;
      return EventFetchResult(error: e);
    }
  }

  /// Radar entry: automatic fetch follows the settings switch. A driver tap
  /// always fetches, even when the switch is off.
  static Future<EventFetchResult> loadForDisplay({required bool userAsked}) async {
    var allow = userAsked;
    if (!allow) {
      try {
        final prefs = await SharedPreferences.getInstance();
        allow = GithubAccess.autoEvents(prefs);
      } catch (_) {
        allow = false;
      }
    }
    return load(allowNetwork: allow, forceRefresh: userAsked);
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
    final uri = Uri.parse(_eventsUrl);
    GithubHttp.note(uri);
    final client = GithubHttp.open();
    try {
      client.connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      
      final response = await request.close().timeout(const Duration(seconds: 10));

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(body);
      final now = DateTime.now();
      // Keep events that started within the last 2 hours visible.
      final List<EventModel> events = parseRemoteEvents(decoded, now: now)
          .where((event) => event.date.isAfter(now.subtract(const Duration(hours: 2))))
          .toList();

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

  static bool _isFresh(DateTime? at) {
    if (at == null) return false;
    return DateTime.now().difference(at) < _cacheValidity;
  }

  static EventFetchResult? _freshMemory() {
    final memory = _memoryResult();
    if (memory == null || !_isFresh(memory.fetchedAt)) return null;
    return memory;
  }

  static EventFetchResult? _memoryResult() {
    final events = _cachedEvents;
    final at = _cacheTimestamp;
    if (events == null || at == null) return null;
    return EventFetchResult(events: events, fetchedAt: at);
  }

  static void _remember(List<EventModel> events, DateTime at) {
    _cachedEvents = events;
    _cacheTimestamp = at;
  }

  static Future<EventFetchResult?> _readStored() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(eventsCacheJsonKey);
      final ms = prefs.getInt(eventsCacheAtKey);
      if (raw == null || raw.isEmpty || ms == null || ms <= 0) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final events = <EventModel>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        events.add(EventModel.fromJson(Map<String, dynamic>.from(item)));
      }
      return EventFetchResult(
        events: events,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(ms),
      );
    } catch (e, s) {
      loge('event cache unreadable', name: 'events', error: e, stack: s);
      return null;
    }
  }

  static Future<void> _writeStored(EventFetchResult result) async {
    final events = result.events;
    final at = result.fetchedAt;
    if (events == null || at == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        eventsCacheJsonKey,
        jsonEncode(events.map((event) => event.toJson()).toList()),
      );
      await prefs.setInt(eventsCacheAtKey, at.millisecondsSinceEpoch);
    } catch (e, s) {
      loge('event cache write failed', name: 'events', error: e, stack: s);
    }
  }

  /// Validates one remote radar payload.
  ///
  /// A non-array document throws [FormatException] (the fetch retries).
  /// A bad item is skipped so one malformed object does not drop the rest.
  /// Title and venue are capped; dates more than [maxDateSkew] from [now]
  /// are rejected.
  static List<EventModel> parseRemoteEvents(Object? decoded, {DateTime? now}) {
    if (decoded is! List) {
      throw const FormatException('Expected JSON array');
    }
    final clock = now ?? DateTime.now();
    final events = <EventModel>[];
    for (final item in decoded) {
      try {
        final event = _validatedEvent(item, clock);
        if (event == null) {
          logd('Skipping malformed event item', name: 'events');
          continue;
        }
        events.add(event);
      } catch (e) {
        logd('Skipping malformed event item: $e', name: 'events');
      }
    }
    return events;
  }

  static EventModel? _validatedEvent(Object? item, DateTime now) {
    if (item is! Map) return null;
    final title = _cappedString(item['title'], maxTitleChars);
    if (title == null || title.isEmpty) return null;
    final date = _boundedDate(item['date'], now);
    if (date == null) return null;

    final venueRaw = item['venue'];
    final String venue;
    if (venueRaw == null) {
      venue = S.unknownVenue;
    } else {
      final capped = _cappedString(venueRaw, maxVenueChars);
      if (capped == null) return null;
      venue = capped.isEmpty ? S.unknownVenue : capped;
    }

    final surge = _cappedString(item['surgeLevel'], maxSurgeChars);
    final surgeLevel = (surge == null || surge.isEmpty) ? 'Low' : surge;
    return EventModel(
      title: title,
      venue: venue,
      date: date,
      surgeLevel: surgeLevel,
    );
  }

  /// Trims and caps a string field. Non-strings are malformed (`null`).
  static String? _cappedString(Object? value, int maxChars) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return trimmed.substring(0, maxChars);
  }

  static DateTime? _boundedDate(Object? value, DateTime now) {
    if (value is! String || value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) return null;
    final earliest = now.subtract(maxDateSkew);
    final latest = now.add(maxDateSkew);
    if (parsed.isBefore(earliest) || parsed.isAfter(latest)) return null;
    return parsed;
  }
}
