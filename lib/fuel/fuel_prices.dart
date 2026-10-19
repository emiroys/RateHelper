import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'orlen_stations.dart';

/// Accepted PLN/litre ranges, inclusive. LPG sells near 3 zł, so it cannot
/// share the PB95 floor. `RANGES` in the Worker must match.
const double kPb95MinPrice = 4.00;
const double kPb95MaxPrice = 9.00;
const double kLpgMinPrice = 2.00;
const double kLpgMaxPrice = 5.00;

(double, double) priceRange(FuelType fuel) => switch (fuel) {
  FuelType.pb95 => (kPb95MinPrice, kPb95MaxPrice),
  FuelType.lpg => (kLpgMinPrice, kLpgMaxPrice),
};

/// Published timestamps further than this from now are treated as garbage.
const Duration kMaxPriceAge = Duration(days: 365);
const Duration _maxFutureSkew = Duration(hours: 1);

@immutable
class FuelPrice {
  const FuelPrice({required this.price, required this.updatedAt});

  final double price;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
    'price': price,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is FuelPrice &&
      other.price == price &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(price, updatedAt);
}

@immutable
class StationPrices {
  const StationPrices({this.pb95, this.lpg});

  static const empty = StationPrices();

  final FuelPrice? pb95;
  final FuelPrice? lpg;

  FuelPrice? of(FuelType fuel) => switch (fuel) {
    FuelType.pb95 => pb95,
    FuelType.lpg => lpg,
  };

  Map<String, Object> toJson() => {
    if (pb95 != null) FuelType.pb95.wireName: pb95!.toJson(),
    if (lpg != null) FuelType.lpg.wireName: lpg!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is StationPrices && other.pb95 == pb95 && other.lpg == lpg;

  @override
  int get hashCode => Object.hash(pb95, lpg);
}

/// Station id → published prices.
typedef PriceBook = Map<String, StationPrices>;

double roundPrice(double value) => (value * 100).roundToDouble() / 100;

bool isPriceInRange(FuelType fuel, double value) {
  final (min, max) = priceRange(fuel);
  return value >= min && value <= max;
}

/// Validates the `/prices` document. Unknown stations, out-of-range prices,
/// and implausible timestamps are dropped one by one, so one bad entry does
/// not hide the rest. A document that is not `{"stations": {...}}` throws.
PriceBook parsePriceBook(Object? decoded, {DateTime? now}) {
  if (decoded is! Map || decoded['stations'] is! Map) {
    throw const FormatException('Expected {"stations": {...}}');
  }
  final clock = now ?? DateTime.now();
  final stations = decoded['stations'] as Map;
  final book = <String, StationPrices>{};
  for (final entry in stations.entries) {
    final id = entry.key;
    if (id is! String) continue;
    final station = stationById(id);
    if (station == null || entry.value is! Map) continue;
    final raw = entry.value as Map;
    final pb95 = _parsePrice(FuelType.pb95, raw, clock);
    final lpg = station.sellsLpg ? _parsePrice(FuelType.lpg, raw, clock) : null;
    if (pb95 == null && lpg == null) continue;
    book[id] = StationPrices(pb95: pb95, lpg: lpg);
  }
  return book;
}

FuelPrice? _parsePrice(FuelType fuel, Map station, DateTime now) {
  final raw = station[fuel.wireName];
  if (raw is! Map) return null;
  final price = raw['price'];
  final at = raw['updatedAt'];
  if (price is! num || at is! String) return null;
  final value = roundPrice(price.toDouble());
  if (!isPriceInRange(fuel, value)) return null;
  final updatedAt = DateTime.tryParse(at);
  if (updatedAt == null) return null;
  if (updatedAt.isAfter(now.add(_maxFutureSkew))) return null;
  if (updatedAt.isBefore(now.subtract(kMaxPriceAge))) return null;
  return FuelPrice(price: value, updatedAt: updatedAt);
}

Map<String, Object> encodePriceBook(PriceBook book) => {
  'stations': {
    for (final entry in book.entries) entry.key: entry.value.toJson(),
  },
};

enum PriceInputError { empty, notANumber, tooPrecise, outOfRange }

@immutable
class PriceInput {
  const PriceInput._(this.value, this.error);

  final double? value;
  final PriceInputError? error;

  bool get isValid => value != null;
}

/// Parses what the driver typed. Accepts `6.29`, `6,29`, and `6`; rejects
/// more than two decimals and anything outside [priceRange] for [fuel].
PriceInput validatePriceInput(String raw, FuelType fuel) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return const PriceInput._(null, PriceInputError.empty);
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) {
    return const PriceInput._(null, PriceInputError.notANumber);
  }
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) {
    return const PriceInput._(null, PriceInputError.tooPrecise);
  }
  final value = roundPrice(double.parse(text));
  if (!isPriceInRange(fuel, value)) {
    return const PriceInput._(null, PriceInputError.outOfRange);
  }
  return PriceInput._(value, null);
}

String formatPrice(double value) => value.toStringAsFixed(2);

@immutable
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;
}

const double _earthRadiusKm = 6371.0088;

/// Great-circle distance in kilometres.
double haversineKm(GeoPoint a, GeoPoint b) {
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
}

String formatDistanceKm(double km) => '${km.toStringAsFixed(1)} km';

enum FuelSort { cheapest, nearest }

@immutable
class StationView {
  const StationView({
    required this.station,
    required this.prices,
    this.distanceKm,
  });

  final OrlenStation station;
  final StationPrices prices;
  final double? distanceKm;
}

/// Orders the stations for one chip. Stations without the sorted value
/// (no price at all, or no position) keep their list order at the bottom.
///
/// "Cheapest" ranks PB95 and LPG together: each known price is divided by
/// the cheapest price for that fuel, and the station's score is the average,
/// so a station with only one reported fuel still compares fairly.
List<StationView> sortStations({
  required List<OrlenStation> stations,
  required PriceBook prices,
  required FuelSort sort,
  GeoPoint? position,
}) {
  final views = [
    for (final station in stations)
      StationView(
        station: station,
        prices: prices[station.id] ?? StationPrices.empty,
        distanceKm: position == null
            ? null
            : haversineKm(position, GeoPoint(station.lat, station.lng)),
      ),
  ];
  final cheapest = <FuelType, double>{};
  for (final view in views) {
    for (final fuel in FuelType.values) {
      final price = view.prices.of(fuel)?.price;
      final best = cheapest[fuel];
      if (price != null && (best == null || price < best)) {
        cheapest[fuel] = price;
      }
    }
  }
  double? priceScore(StationView view) {
    var sum = 0.0;
    var count = 0;
    for (final fuel in FuelType.values) {
      final price = view.prices.of(fuel)?.price;
      if (price == null) continue;
      sum += price / cheapest[fuel]!;
      count++;
    }
    return count == 0 ? null : sum / count;
  }

  double? key(StationView view) => switch (sort) {
    FuelSort.cheapest => priceScore(view),
    FuelSort.nearest => view.distanceKm,
  };
  final indexed = views.indexed.toList();
  indexed.sort((a, b) {
    final ka = key(a.$2);
    final kb = key(b.$2);
    if (ka == null && kb == null) return a.$1.compareTo(b.$1);
    if (ka == null) return 1;
    if (kb == null) return -1;
    final byKey = ka.compareTo(kb);
    return byKey != 0 ? byKey : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}
