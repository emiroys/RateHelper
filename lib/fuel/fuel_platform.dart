import 'package:flutter/services.dart';

import '../log.dart';
import 'fuel_prices.dart';
import 'orlen_stations.dart';

enum LocationFailure { denied, disabled, unavailable }

class LocationResult {
  const LocationResult.found(GeoPoint this.position) : failure = null;
  const LocationResult.failed(LocationFailure this.failure) : position = null;

  final GeoPoint? position;
  final LocationFailure? failure;
}

/// One position fix for the "Nearest" chip. Nothing is stored or sent;
/// distances are computed on the device.
abstract class FuelLocator {
  Future<LocationResult> currentPosition();

  Future<bool> openAppSettings();
}

/// `MainActivity.getCurrentLocation`: asks for the location permission when
/// needed, then returns one `LocationManager` fix (or a recent last-known).
class NativeFuelLocator implements FuelLocator {
  const NativeFuelLocator();

  static const MethodChannel _channel = MethodChannel(
    'com.ratehelper.app/system',
  );

  @override
  Future<LocationResult> currentPosition() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'getCurrentLocation',
      );
      return parseLocationReply(raw);
    } on Exception catch (e, s) {
      loge('location request failed', name: 'fuel', error: e, stack: s);
      return const LocationResult.failed(LocationFailure.unavailable);
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppDetails') ?? false;
    } on Exception {
      return false;
    }
  }
}

LocationResult parseLocationReply(Map<String, Object?>? raw) {
  if (raw == null) {
    return const LocationResult.failed(LocationFailure.unavailable);
  }
  switch (raw['error']) {
    case 'denied':
      return const LocationResult.failed(LocationFailure.denied);
    case 'disabled':
      return const LocationResult.failed(LocationFailure.disabled);
  }
  final lat = raw['lat'];
  final lng = raw['lng'];
  if (lat is! num || lng is! num) {
    return const LocationResult.failed(LocationFailure.unavailable);
  }
  final latD = lat.toDouble();
  final lngD = lng.toDouble();
  if (latD.abs() > 90 || lngD.abs() > 180) {
    return const LocationResult.failed(LocationFailure.unavailable);
  }
  return LocationResult.found(GeoPoint(latD, lngD));
}

enum NavApp { googleMaps, waze }

/// Universal links: the Maps / Waze app opens them when installed, the
/// browser otherwise. Both shapes are allowlisted in `MainActivity`.
String navigationUrl(OrlenStation station, NavApp app) {
  final ll = '${station.lat},${station.lng}';
  return switch (app) {
    NavApp.googleMaps => Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': ll,
      'travelmode': 'driving',
    }).toString(),
    NavApp.waze => Uri.https('waze.com', '/ul', {
      'll': ll,
      'navigate': 'yes',
    }).toString(),
  };
}
