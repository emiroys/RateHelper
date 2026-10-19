import 'package:flutter/foundation.dart';

/// The two fuels the tracker follows. [wireName] is the key used by the
/// price API and the Cloudflare Worker; do not rename it.
enum FuelType {
  pb95('pb95'),
  lpg('lpg');

  const FuelType(this.wireName);

  final String wireName;

  static FuelType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

@immutable
class OrlenStation {
  const OrlenStation({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.sellsLpg = true,
  });

  /// Stable key shared with `backend/orlen-worker/src/stations.js`.
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;

  /// False only where OpenStreetMap records `fuel:lpg=no`.
  final bool sellsLpg;

  bool sells(FuelType fuel) => fuel == FuelType.pb95 || sellsLpg;
}

/// Orlen stations inside Kraków city limits.
///
/// Coordinates come from OpenStreetMap (brand=Orlen, ODbL), checked against
/// Nominatim in October 2026. Entries without a house number had none in
/// OSM; the street is the one the station sits on.
const List<OrlenStation> krakowOrlenStations = [
  OrlenStation(
    id: 'nowohucka-71',
    name: 'ORLEN Nowohucka',
    address: 'ul. Nowohucka 71',
    lat: 50.0462069,
    lng: 19.9777390,
  ),
  OrlenStation(
    id: 'sliwiaka-34',
    name: 'ORLEN Śliwiaka',
    address: 'ul. Tadeusza Śliwiaka 34',
    lat: 50.0375555,
    lng: 20.0510747,
  ),
  OrlenStation(
    id: 'centralna-62',
    name: 'ORLEN Centralna',
    address: 'ul. Centralna 62',
    lat: 50.0639129,
    lng: 20.0045976,
  ),
  OrlenStation(
    id: 'pilotow-4b',
    name: 'ORLEN Pilotów',
    address: 'ul. Pilotów 4B',
    lat: 50.0789800,
    lng: 19.9709435,
  ),
  OrlenStation(
    id: 'jasnogorska-2b',
    name: 'ORLEN Jasnogórska',
    address: 'ul. Jasnogórska 2B',
    lat: 50.0896573,
    lng: 19.8931029,
  ),
  OrlenStation(
    id: 'zakopianska-58',
    name: 'ORLEN Zakopiańska (Borek Fałęcki)',
    address: 'ul. Zakopiańska 58',
    lat: 50.0179129,
    lng: 19.9323076,
  ),
  OrlenStation(
    id: 'zakopianska-289',
    name: 'ORLEN Zakopiańska (Opatkowice)',
    address: 'ul. Zakopiańska 289',
    lat: 49.9842201,
    lng: 19.9121459,
  ),
  OrlenStation(
    id: 'grota-roweckiego-33',
    name: 'ORLEN Grota-Roweckiego',
    address: 'ul. Stefana Grota-Roweckiego 33',
    lat: 50.0291779,
    lng: 19.9123584,
  ),
  OrlenStation(
    id: 'armii-krajowej-21a',
    name: 'ORLEN Armii Krajowej',
    address: 'ul. Armii Krajowej 21A',
    lat: 50.0711027,
    lng: 19.8930072,
  ),
  OrlenStation(
    id: 'olszanicka-174',
    name: 'ORLEN Olszanicka',
    address: 'ul. Olszanicka 174',
    lat: 50.0733846,
    lng: 19.8083585,
  ),
  OrlenStation(
    id: 'skotnicka-242',
    name: 'ORLEN Skotnicka',
    address: 'ul. Skotnicka 242',
    lat: 50.0007956,
    lng: 19.8639472,
  ),
  OrlenStation(
    id: 'zawila-62',
    name: 'ORLEN Zawiła',
    address: 'ul. Zawiła 62',
    lat: 50.0063089,
    lng: 19.8980169,
  ),
  OrlenStation(
    id: 'luzycka-40',
    name: 'ORLEN Łużycka',
    address: 'ul. Łużycka 40',
    lat: 50.0132593,
    lng: 19.9663781,
  ),
  OrlenStation(
    id: 'tyniecka-186',
    name: 'ORLEN Tyniecka',
    address: 'ul. Tyniecka 186',
    lat: 50.0236995,
    lng: 19.8300471,
  ),
  OrlenStation(
    id: 'kamienna-18',
    name: 'ORLEN Kamienna',
    address: 'ul. Kamienna 18',
    lat: 50.0773591,
    lng: 19.9476643,
  ),
  OrlenStation(
    id: 'wybickiego-3e',
    name: 'ORLEN Wybickiego',
    address: 'ul. Józefa Wybickiego 3E',
    lat: 50.0834043,
    lng: 19.9290119,
  ),
  OrlenStation(
    id: 'okulickiego-61',
    name: 'ORLEN Okulickiego',
    address: 'ul. Gen. Leopolda Okulickiego 61',
    lat: 50.0930738,
    lng: 20.0263477,
  ),
  OrlenStation(
    id: 'andersa',
    name: 'ORLEN Andersa',
    address: 'al. Gen. Władysława Andersa',
    lat: 50.0879871,
    lng: 20.0055144,
  ),
  OrlenStation(
    id: 'palacha',
    name: 'ORLEN Palacha',
    address: 'ul. Jana Palacha',
    lat: 50.0898011,
    lng: 19.9180492,
  ),
  OrlenStation(
    id: 'mogilska',
    name: 'ORLEN Mogilska',
    address: 'ul. Mogilska',
    lat: 50.0689480,
    lng: 19.9794727,
  ),
  OrlenStation(
    id: 'bulwarowa',
    name: 'ORLEN Bulwarowa',
    address: 'ul. Bulwarowa',
    lat: 50.0690823,
    lng: 20.0525792,
  ),
  OrlenStation(
    id: 'igolomska',
    name: 'ORLEN Igołomska',
    address: 'ul. Igołomska',
    lat: 50.0747437,
    lng: 20.1404703,
  ),
  OrlenStation(
    id: 'daszynskiego',
    name: 'ORLEN Daszyńskiego',
    address: 'al. Ignacego Daszyńskiego',
    lat: 50.0518180,
    lng: 19.9542534,
  ),
  OrlenStation(
    id: 'wloczkow',
    name: 'ORLEN Włóczków',
    address: 'ul. Włóczków',
    lat: 50.0551220,
    lng: 19.9251924,
    sellsLpg: false,
  ),
  OrlenStation(
    id: 'wioslarska',
    name: 'ORLEN Wioślarska',
    address: 'ul. Wioślarska',
    lat: 50.0479792,
    lng: 19.9024110,
  ),
  OrlenStation(
    id: 'zamknieta',
    name: 'ORLEN Zamknięta',
    address: 'ul. Zamknięta',
    lat: 50.0398860,
    lng: 19.9625541,
  ),
  OrlenStation(
    id: 'jerzmanowskiego',
    name: 'ORLEN Jerzmanowskiego',
    address: 'ul. Erazma Jerzmanowskiego',
    lat: 50.0105966,
    lng: 20.0096518,
  ),
  OrlenStation(
    id: 'bunscha',
    name: 'ORLEN Bunscha',
    address: 'ul. Karola Bunscha',
    lat: 50.0082233,
    lng: 19.8805957,
  ),
];

OrlenStation? stationById(String id) {
  for (final station in krakowOrlenStations) {
    if (station.id == id) return station;
  }
  return null;
}
