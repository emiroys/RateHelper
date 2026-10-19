import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/fuel/fuel_api.dart';
import 'package:rate_helper/fuel/fuel_platform.dart';
import 'package:rate_helper/app_colors.dart';
import 'package:rate_helper/earnings_models.dart';
import 'package:rate_helper/fuel/fuel_prices.dart';
import 'package:rate_helper/fuel/fuel_receipts.dart';
import 'package:rate_helper/fuel/fuel_screen.dart';
import 'package:rate_helper/fuel/orlen_stations.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:rate_helper/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.utc(2026, 10, 17, 10);

FuelPrice _price(double value, {Duration age = const Duration(hours: 2)}) =>
    FuelPrice(price: value, updatedAt: _now.subtract(age));

class _FakeApi implements FuelPriceApi {
  _FakeApi({
    this.book = const {},
    this.outcome = SubmitOutcome.pending,
    this.failFetch = false,
  });

  PriceBook book;
  SubmitOutcome outcome;
  bool failFetch;
  int fetches = 0;
  final submissions = <PriceSubmission>[];

  @override
  Future<PriceBook> fetchPrices() async {
    fetches++;
    if (failFetch) throw const HttpException('offline');
    return book;
  }

  @override
  Future<SubmitOutcome> submit(PriceSubmission submission) async {
    submissions.add(submission);
    return outcome;
  }
}

class _FakeLocator implements FuelLocator {
  _FakeLocator(this.result);

  LocationResult result;
  int calls = 0;
  int settingsOpened = 0;

  @override
  Future<LocationResult> currentPosition() async {
    calls++;
    return result;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }
}

/// Near ORLEN Pilotów 4B.
const _nearPilotow = GeoPoint(50.0785, 19.9700);

final _samplePrices = <String, StationPrices>{
  'nowohucka-71': StationPrices(pb95: _price(6.49), lpg: _price(3.19)),
  'sliwiaka-34': StationPrices(pb95: _price(6.19), lpg: _price(3.29)),
  'centralna-62': StationPrices(lpg: _price(2.99)),
  'pilotow-4b': StationPrices(pb95: _price(6.09)),
};

List<String> _cardOrder(WidgetTester tester) {
  final cards = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> &&
        key.value.startsWith('fuel-station-') &&
        key.value != 'fuel-station-list';
  });
  final entries = [
    for (final element in cards.evaluate())
      (
        (element.widget.key! as ValueKey<String>).value.substring(
          'fuel-station-'.length,
        ),
        tester.getTopLeft(find.byWidget(element.widget)).dy,
      ),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final e in entries) e.$1];
}

/// In-memory stand-in for [FuelReceiptStore].
class _FakeReceipts {
  _FakeReceipts([List<FuelReceipt>? initial]) : receipts = [...?initial];

  final List<FuelReceipt> receipts;
  final saved = <double>[];

  Future<int> save(double amount) async {
    saved.add(amount);
    receipts.add(FuelReceipt(timestamp: _now, amountPaid: amount));
    return receipts.length;
  }

  Future<List<FuelReceipt>> load() async => List.of(receipts);
}

Future<void> _pumpFuel(
  WidgetTester tester, {
  FuelPriceApi? api,
  FuelLocator? locator,
  List<String>? opened,
  bool openSucceeds = true,
  Size size = const Size(411, 914),
  FuelTab initialTab = FuelTab.stations,
  _FakeReceipts? receipts,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final store = receipts ?? _FakeReceipts();
  await tester.pumpWidget(
    MaterialApp(
      home: FuelScreen(
        api: api,
        initialTab: initialTab,
        locator:
            locator ?? _FakeLocator(const LocationResult.found(_nearPilotow)),
        openUrl: (url) async {
          opened?.add(url);
          return openSucceeds;
        },
        now: () => _now,
        saveReceipt: store.save,
        loadReceipts: store.load,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    S.setLang(AppLang.en);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => S.setLang(AppLang.tr));

  group('station database', () {
    test('ids are unique and slug-shaped', () {
      final ids = krakowOrlenStations.map((s) => s.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[a-z0-9-]{3,40}$')));
      }
    });

    test('every station is inside Kraków with a name and address', () {
      expect(krakowOrlenStations.length, greaterThanOrEqualTo(25));
      for (final s in krakowOrlenStations) {
        expect(s.lat, inInclusiveRange(49.96, 50.13), reason: s.id);
        expect(s.lng, inInclusiveRange(19.78, 20.23), reason: s.id);
        expect(s.name, startsWith('ORLEN '));
        expect(s.address.trim(), isNotEmpty);
      }
    });

    test('includes the well-known city stations', () {
      final addresses = krakowOrlenStations.map((s) => s.address).join('|');
      for (final street in [
        'Nowohucka 71',
        'Śliwiaka 34',
        'Centralna 62',
        'Pilotów 4B',
        'Jasnogórska 2B',
        'Zakopiańska 58',
        'Grota-Roweckiego 33',
        'Armii Krajowej 21A',
      ]) {
        expect(addresses, contains(street));
      }
    });

    test('the Worker lists exactly the same stations', () {
      final js = File(
        'backend/orlen-worker/src/stations.js',
      ).readAsStringSync();
      final workerIds = RegExp(
        r"^\s*'([a-z0-9-]+)':\s*\{",
        multiLine: true,
      ).allMatches(js).map((m) => m.group(1)).toSet();
      expect(workerIds, krakowOrlenStations.map((s) => s.id).toSet());

      final noLpg = RegExp(
        r"^\s*'([a-z0-9-]+)':.*lpg: false",
        multiLine: true,
      ).allMatches(js).map((m) => m.group(1)).toSet();
      expect(
        noLpg,
        krakowOrlenStations.where((s) => !s.sellsLpg).map((s) => s.id).toSet(),
      );
    });

    test('FuelType wire names are stable', () {
      expect(FuelType.pb95.wireName, 'pb95');
      expect(FuelType.lpg.wireName, 'lpg');
      expect(FuelType.fromWire('lpg'), FuelType.lpg);
      expect(FuelType.fromWire('diesel'), isNull);
    });
  });

  group('validatePriceInput', () {
    test('accepts dot, comma, and whole numbers rounded to 2 decimals', () {
      expect(validatePriceInput('6.29', FuelType.pb95).value, 6.29);
      expect(validatePriceInput(' 6,29 ', FuelType.pb95).value, 6.29);
      expect(validatePriceInput('6', FuelType.pb95).value, 6.0);
      expect(validatePriceInput('3.1', FuelType.lpg).value, 3.1);
    });

    test('PB95 bounds are 4.00 – 9.00 inclusive', () {
      expect(validatePriceInput('4.00', FuelType.pb95).isValid, isTrue);
      expect(validatePriceInput('9.00', FuelType.pb95).isValid, isTrue);
      expect(
        validatePriceInput('3.99', FuelType.pb95).error,
        PriceInputError.outOfRange,
      );
      expect(
        validatePriceInput('9.01', FuelType.pb95).error,
        PriceInputError.outOfRange,
      );
    });

    test('LPG bounds are 2.00 – 5.00 inclusive', () {
      expect(validatePriceInput('2.00', FuelType.lpg).isValid, isTrue);
      expect(validatePriceInput('5,00', FuelType.lpg).isValid, isTrue);
      expect(
        validatePriceInput('1.99', FuelType.lpg).error,
        PriceInputError.outOfRange,
      );
      expect(
        validatePriceInput('6.29', FuelType.lpg).error,
        PriceInputError.outOfRange,
      );
    });

    test('rejects junk with a specific reason', () {
      expect(
        validatePriceInput('', FuelType.pb95).error,
        PriceInputError.empty,
      );
      expect(
        validatePriceInput('abc', FuelType.pb95).error,
        PriceInputError.notANumber,
      );
      expect(
        validatePriceInput('6..2', FuelType.pb95).error,
        PriceInputError.notANumber,
      );
      expect(
        validatePriceInput('-6', FuelType.pb95).error,
        PriceInputError.notANumber,
      );
      expect(
        validatePriceInput('6.299', FuelType.pb95).error,
        PriceInputError.tooPrecise,
      );
    });

    test('formatPrice always shows two decimals', () {
      expect(formatPrice(6.0), '6.00');
      expect(formatPrice(3.1), '3.10');
    });
  });

  group('haversine distance', () {
    test('Rynek Główny to Wawel is about 0.85 km', () {
      final km = haversineKm(
        const GeoPoint(50.0617, 19.9373),
        const GeoPoint(50.0541, 19.9354),
      );
      expect(km, closeTo(0.85, 0.05));
    });

    test('Kraków to Warsaw is about 252 km and symmetric', () {
      const krk = GeoPoint(50.0647, 19.9450);
      const waw = GeoPoint(52.2297, 21.0122);
      expect(haversineKm(krk, waw), closeTo(252, 3));
      expect(haversineKm(krk, waw), closeTo(haversineKm(waw, krk), 1e-9));
      expect(haversineKm(krk, krk), 0);
    });

    test('formats as one-decimal km', () {
      expect(formatDistanceKm(1.234), '1.2 km');
      expect(formatDistanceKm(0.04), '0.0 km');
    });
  });

  group('sortStations', () {
    test('cheapest ranks PB95 and LPG together, no price keeps order last', () {
      final views = sortStations(
        stations: krakowOrlenStations,
        prices: _samplePrices,
        sort: FuelSort.cheapest,
      );
      // centralna (cheapest LPG) and pilotow (cheapest PB95) tie at 1.0 and
      // keep list order; sliwiaka averages 1.058, nowohucka 1.066.
      const priced = [
        'centralna-62',
        'pilotow-4b',
        'sliwiaka-34',
        'nowohucka-71',
      ];
      expect(views.take(4).map((v) => v.station.id), priced);
      final rest = views.skip(4).map((v) => v.station.id).toList();
      final expectedRest = krakowOrlenStations
          .map((s) => s.id)
          .where((id) => !priced.contains(id))
          .toList();
      expect(rest, expectedRest);
    });

    test('a station cheap on both fuels beats one cheap on only one', () {
      final views = sortStations(
        stations: krakowOrlenStations,
        prices: {
          'nowohucka-71': StationPrices(pb95: _price(6.50), lpg: _price(3.00)),
          'sliwiaka-34': StationPrices(pb95: _price(6.00), lpg: _price(3.40)),
          'centralna-62': StationPrices(pb95: _price(6.05), lpg: _price(3.05)),
        },
        sort: FuelSort.cheapest,
      );
      expect(views.first.station.id, 'centralna-62');
    });

    test('equal prices keep list order', () {
      final views = sortStations(
        stations: krakowOrlenStations,
        prices: {
          'sliwiaka-34': StationPrices(lpg: _price(3.00)),
          'nowohucka-71': StationPrices(lpg: _price(3.00)),
        },
        sort: FuelSort.cheapest,
      );
      expect(views.take(2).map((v) => v.station.id), [
        'nowohucka-71',
        'sliwiaka-34',
      ]);
    });

    test('nearest sorts by distance and fills distanceKm', () {
      final views = sortStations(
        stations: krakowOrlenStations,
        prices: const {},
        sort: FuelSort.nearest,
        position: _nearPilotow,
      );
      expect(views.first.station.id, 'pilotow-4b');
      for (var i = 1; i < views.length; i++) {
        expect(
          views[i].distanceKm!,
          greaterThanOrEqualTo(views[i - 1].distanceKm!),
        );
      }
    });

    test('nearest without a position keeps list order', () {
      final views = sortStations(
        stations: krakowOrlenStations,
        prices: const {},
        sort: FuelSort.nearest,
      );
      expect(
        views.map((v) => v.station.id),
        krakowOrlenStations.map((s) => s.id),
      );
      expect(views.every((v) => v.distanceKm == null), isTrue);
    });
  });

  group('parsePriceBook', () {
    Map<String, Object> doc(Map<String, Object> stations) => {
      'stations': stations,
    };
    String iso(Duration age) => _now.subtract(age).toIso8601String();

    test('reads valid prices and round-trips through encodePriceBook', () {
      final book = parsePriceBook(
        doc({
          'nowohucka-71': {
            'pb95': {'price': 6.49, 'updatedAt': iso(const Duration(hours: 1))},
            'lpg': {'price': 3.19, 'updatedAt': iso(const Duration(hours: 2))},
          },
        }),
        now: _now,
      );
      expect(book['nowohucka-71']!.pb95!.price, 6.49);
      expect(book['nowohucka-71']!.lpg!.price, 3.19);
      final again = parsePriceBook(
        jsonDecode(jsonEncode(encodePriceBook(book))),
        now: _now,
      );
      expect(again, book);
    });

    test('drops unknown stations, bad prices, and bad dates', () {
      final book = parsePriceBook(
        doc({
          'not-a-station': {
            'pb95': {'price': 6.0, 'updatedAt': iso(Duration.zero)},
          },
          'sliwiaka-34': {
            'pb95': {'price': 12.0, 'updatedAt': iso(Duration.zero)},
            'lpg': {'price': 3.2, 'updatedAt': 'yesterday'},
          },
          'centralna-62': {
            'pb95': {'price': '6.10', 'updatedAt': iso(Duration.zero)},
            'lpg': {'price': 3.2, 'updatedAt': iso(const Duration(days: -1))},
          },
          'pilotow-4b': {
            'pb95': {'price': 6.1, 'updatedAt': iso(const Duration(days: 400))},
            'lpg': {'price': 3.05, 'updatedAt': iso(Duration.zero)},
          },
          'wloczkow': {
            'lpg': {'price': 3.0, 'updatedAt': iso(Duration.zero)},
          },
        }),
        now: _now,
      );
      expect(book.keys, ['pilotow-4b']);
      expect(book['pilotow-4b']!.pb95, isNull);
      expect(book['pilotow-4b']!.lpg!.price, 3.05);
    });

    test('a document without stations throws', () {
      expect(() => parsePriceBook([]), throwsFormatException);
      expect(() => parsePriceBook({'stations': []}), throwsFormatException);
    });
  });

  group('API config', () {
    test('only https base URLs are accepted, trailing slash trimmed', () {
      expect(
        FuelPriceApi.parseBaseUrl('https://x.workers.dev/').toString(),
        'https://x.workers.dev',
      );
      expect(
        FuelPriceApi.parseBaseUrl('https://x.dev/api').toString(),
        'https://x.dev/api',
      );
      expect(FuelPriceApi.parseBaseUrl(''), isNull);
      expect(FuelPriceApi.parseBaseUrl('http://x.dev'), isNull);
      expect(FuelPriceApi.parseBaseUrl('https://x.dev?a=1'), isNull);
      expect(FuelPriceApi.parseBaseUrl('https://u:p@x.dev'), isNull);
      expect(FuelPriceApi.parseBaseUrl('not a url'), isNull);
    });

    test('public builds have no endpoint; mock is opt-in', () {
      expect(FuelPriceApi.fromEnvironment(), isNull);
      expect(FuelPriceApi.fromConfig('mock'), isA<MockFuelPriceApi>());
      expect(
        FuelPriceApi.fromConfig('https://x.workers.dev'),
        isA<HttpFuelPriceApi>(),
      );
    });

    test('mock backend validates and publishes immediately', () async {
      final api = MockFuelPriceApi(now: () => _now);
      expect(
        await api.submit(
          const PriceSubmission(
            stationId: 'wloczkow',
            fuel: FuelType.lpg,
            price: 3.0,
          ),
        ),
        SubmitOutcome.invalid,
      );
      expect(
        await api.submit(
          const PriceSubmission(
            stationId: 'nowohucka-71',
            fuel: FuelType.lpg,
            price: 3.15,
          ),
        ),
        SubmitOutcome.pending,
      );
      final book = await api.fetchPrices();
      expect(
        book['nowohucka-71']!.lpg,
        FuelPrice(price: 3.15, updatedAt: _now),
      );
    });
  });

  group('HttpFuelPriceApi against a local server', () {
    late HttpServer server;
    final received = <String>[];
    var submitStatus = HttpStatus.accepted;

    setUp(() async {
      received.clear();
      submitStatus = HttpStatus.accepted;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        received.add('${request.method} ${request.uri.path} $body');
        if (request.uri.path == '/api/prices') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'stations': {
                  'pilotow-4b': {
                    'pb95': {
                      'price': 6.09,
                      'updatedAt': DateTime.now().toUtc().toIso8601String(),
                    },
                  },
                },
              }),
            );
        } else if (request.uri.path == '/api/submissions') {
          request.response
            ..statusCode = submitStatus
            ..write('{}');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Future<T> real<T>(
      Future<T> Function(HttpFuelPriceApi api) body, {
      int? port,
    }) {
      return HttpOverrides.runWithHttpOverrides(() {
        final api = HttpFuelPriceApi(
          Uri.parse('http://127.0.0.1:${port ?? server.port}/api'),
        );
        return body(api);
      }, _RealHttp());
    }

    test('fetchPrices parses the /prices document', () async {
      final book = await real((api) => api.fetchPrices());
      expect(book['pilotow-4b']!.pb95!.price, 6.09);
      expect(received.single, startsWith('GET /api/prices'));
    });

    test('submit posts JSON and maps status codes', () async {
      const submission = PriceSubmission(
        stationId: 'pilotow-4b',
        fuel: FuelType.pb95,
        price: 6.19,
      );
      expect(
        await real((api) => api.submit(submission)),
        SubmitOutcome.pending,
      );
      final sent = received.single;
      expect(sent, startsWith('POST /api/submissions '));
      expect(jsonDecode(sent.substring('POST /api/submissions '.length)), {
        'stationId': 'pilotow-4b',
        'fuel': 'pb95',
        'price': 6.19,
      });

      submitStatus = HttpStatus.badRequest;
      expect(
        await real((api) => api.submit(submission)),
        SubmitOutcome.invalid,
      );
      submitStatus = HttpStatus.tooManyRequests;
      expect(
        await real((api) => api.submit(submission)),
        SubmitOutcome.rateLimited,
      );
      submitStatus = HttpStatus.badGateway;
      expect(await real((api) => api.submit(submission)), SubmitOutcome.failed);
    });

    test('an unreachable server is a failed submission, not a throw', () async {
      final port = server.port;
      await server.close(force: true);
      const submission = PriceSubmission(
        stationId: 'pilotow-4b',
        fuel: FuelType.pb95,
        price: 6.19,
      );
      expect(
        await real((api) => api.submit(submission), port: port),
        SubmitOutcome.failed,
      );
    });
  });

  group('platform helpers', () {
    test('location replies are parsed defensively', () {
      final ok = parseLocationReply({'lat': 50.06, 'lng': 19.94});
      expect(ok.position!.lat, 50.06);
      expect(
        parseLocationReply({'error': 'denied'}).failure,
        LocationFailure.denied,
      );
      expect(
        parseLocationReply({'error': 'disabled'}).failure,
        LocationFailure.disabled,
      );
      expect(parseLocationReply(null).failure, LocationFailure.unavailable);
      expect(
        parseLocationReply({'lat': 'x', 'lng': 1}).failure,
        LocationFailure.unavailable,
      );
      expect(
        parseLocationReply({'lat': 91, 'lng': 1}).failure,
        LocationFailure.unavailable,
      );
    });

    test('navigation links use the allowlisted Maps / Waze shapes', () {
      final station = stationById('nowohucka-71')!;
      final maps = Uri.parse(navigationUrl(station, NavApp.googleMaps));
      expect(maps.scheme, 'https');
      expect(maps.host, 'www.google.com');
      expect(maps.path, startsWith('/maps/dir'));
      expect(
        maps.queryParameters['destination'],
        '${station.lat},${station.lng}',
      );
      expect(maps.queryParameters['api'], '1');

      final waze = Uri.parse(navigationUrl(station, NavApp.waze));
      expect(waze.host, 'waze.com');
      expect(waze.path, '/ul');
      expect(waze.queryParameters['ll'], '${station.lat},${station.lng}');
      expect(waze.queryParameters['navigate'], 'yes');
    });
  });

  group('relative time strings', () {
    test('EN / TR / PL', () {
      S.setLang(AppLang.en);
      expect(S.fuelUpdatedAgo(const Duration(seconds: 20)), 'just now');
      expect(S.fuelUpdatedAgo(const Duration(minutes: 5)), '5 min ago');
      expect(S.fuelUpdatedAgo(const Duration(hours: 1)), '1 hour ago');
      expect(S.fuelUpdatedAgo(const Duration(hours: 2)), '2 hours ago');
      expect(S.fuelUpdatedAgo(const Duration(days: 3)), '3 days ago');
      S.setLang(AppLang.tr);
      expect(S.fuelUpdatedAgo(const Duration(hours: 2)), '2 saat önce');
      S.setLang(AppLang.pl);
      expect(S.fuelUpdatedAgo(const Duration(hours: 2)), '2 godz. temu');
      expect(S.fuelUpdatedAgo(const Duration(days: 1)), '1 dzień temu');
    });
  });

  group('FuelPriceCache', () {
    test('round-trips the book and timestamp', () async {
      await FuelPriceCache.write(_samplePrices, _now);
      final cached = await FuelPriceCache.read();
      expect(cached!.fetchedAt, _now.toLocal());
      expect(cached.book['nowohucka-71']!.lpg!.price, 3.19);
    });

    test('garbage in prefs reads as no cache', () async {
      SharedPreferences.setMockInitialValues({
        FuelPriceCache.jsonKey: '{oops',
        FuelPriceCache.atKey: 1,
      });
      expect(await FuelPriceCache.read(), isNull);
    });
  });

  group('FuelScreen', () {
    testWidgets('shows chips, cards, prices, and timestamps', (tester) async {
      final api = _FakeApi(book: _samplePrices);
      await _pumpFuel(tester, api: api);

      expect(find.text('Fuel'), findsOneWidget);
      expect(find.text('Stations'), findsOneWidget);
      expect(find.text('Cheapest'), findsOneWidget);
      expect(find.text('Nearest'), findsOneWidget);
      expect(find.text('Cheapest LPG'), findsNothing);
      expect(find.text('Cheapest PB95'), findsNothing);
      expect(find.text(S.fuelBestCheapest), findsOneWidget);
      expect(api.fetches, 1);

      final card = find.byKey(const ValueKey('fuel-station-centralna-62'));
      expect(
        find.descendant(of: card, matching: find.text('ORLEN Centralna')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('ul. Centralna 62')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('2.99 zł')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('2 hours ago')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('No price yet')),
        findsOneWidget,
      );
      expect(find.text('Prices fetched just now'), findsOneWidget);
    });

    testWidgets('Cheapest and Nearest reorder the list', (tester) async {
      await _pumpFuel(tester, api: _FakeApi(book: _samplePrices));
      expect(_cardOrder(tester).take(3), [
        'centralna-62',
        'pilotow-4b',
        'sliwiaka-34',
      ]);

      await tester.tap(find.byKey(const ValueKey('fuel-sort-nearest')));
      await tester.pumpAndSettle();
      expect(_cardOrder(tester).first, 'pilotow-4b');
      expect(find.text(S.fuelBestNearest), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('fuel-sort-cheapest')));
      await tester.pumpAndSettle();
      expect(_cardOrder(tester).first, 'centralna-62');
    });

    testWidgets('Nearest asks for location once and shows distances', (
      tester,
    ) async {
      final locator = _FakeLocator(const LocationResult.found(_nearPilotow));
      await _pumpFuel(tester, api: _FakeApi(), locator: locator);

      await tester.tap(find.byKey(const ValueKey('fuel-sort-nearest')));
      await tester.pumpAndSettle();
      expect(locator.calls, 1);
      expect(_cardOrder(tester).first, 'pilotow-4b');
      final first = find.byKey(const ValueKey('fuel-station-pilotow-4b'));
      expect(
        find.descendant(of: first, matching: find.text('0.1 km')),
        findsOneWidget,
      );

      // A fresh fix is reused when switching back.
      await tester.tap(find.byKey(const ValueKey('fuel-sort-cheapest')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fuel-sort-nearest')));
      await tester.pumpAndSettle();
      expect(locator.calls, 1);
      expect(_cardOrder(tester).first, 'pilotow-4b');
    });

    testWidgets('denied location keeps the old sort and offers settings', (
      tester,
    ) async {
      final locator = _FakeLocator(
        const LocationResult.failed(LocationFailure.denied),
      );
      await _pumpFuel(
        tester,
        api: _FakeApi(book: _samplePrices),
        locator: locator,
      );

      await tester.tap(find.byKey(const ValueKey('fuel-sort-nearest')));
      await tester.pumpAndSettle();
      expect(find.text(S.fuelLocationDenied), findsOneWidget);
      expect(_cardOrder(tester).first, 'centralna-62');
      expect(find.textContaining(RegExp(r'\d km$')), findsNothing);

      await tester.tap(find.text(S.openSettings));
      await tester.pumpAndSettle();
      expect(locator.settingsOpened, 1);
    });

    testWidgets('location off shows its own message', (tester) async {
      await _pumpFuel(
        tester,
        api: _FakeApi(),
        locator: _FakeLocator(
          const LocationResult.failed(LocationFailure.disabled),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('fuel-sort-nearest')));
      await tester.pumpAndSettle();
      expect(find.text(S.fuelLocationDisabled), findsOneWidget);
    });

    testWidgets('Directions opens Google Maps or Waze for that station', (
      tester,
    ) async {
      final opened = <String>[];
      await _pumpFuel(tester, api: _FakeApi(), opened: opened);
      final station = krakowOrlenStations.first;

      await tester.tap(find.byKey(ValueKey('fuel-directions-${station.id}')));
      await tester.pumpAndSettle();
      expect(find.text(S.fuelNavigateWith), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fuel-nav-googleMaps')));
      await tester.pumpAndSettle();
      expect(opened.single, navigationUrl(station, NavApp.googleMaps));

      await tester.tap(find.byKey(ValueKey('fuel-directions-${station.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fuel-nav-waze')));
      await tester.pumpAndSettle();
      expect(opened.last, navigationUrl(station, NavApp.waze));
    });

    testWidgets('a failed open shows a message', (tester) async {
      await _pumpFuel(tester, api: _FakeApi(), openSucceeds: false);
      final station = krakowOrlenStations.first;
      await tester.tap(find.byKey(ValueKey('fuel-directions-${station.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fuel-nav-googleMaps')));
      await tester.pumpAndSettle();
      expect(find.text(S.fuelOpenNavFailed), findsOneWidget);
    });

    testWidgets('Update price validates before anything is sent', (
      tester,
    ) async {
      final api = _FakeApi();
      await _pumpFuel(tester, api: api);
      const id = 'nowohucka-71';

      await tester.tap(find.byKey(const ValueKey('fuel-update-$id')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('fuel-form-price'));
      final submit = find.byKey(const ValueKey('fuel-form-submit'));

      // LPG is preselected where the station sells it.
      await tester.enterText(field, '1.50');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text(S.fuelPriceOutOfRange('2.00', '5.00')), findsOneWidget);
      expect(api.submissions, isEmpty);

      await tester.tap(find.byKey(const ValueKey('fuel-form-pb95')));
      await tester.pumpAndSettle();
      expect(find.text(S.fuelPriceOutOfRange('4.00', '9.00')), findsOneWidget);

      await tester.enterText(field, '6.299');
      await tester.pumpAndSettle();
      expect(find.text(S.fuelPriceTooPrecise), findsOneWidget);

      await tester.enterText(field, '9.50');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.submissions, isEmpty);

      await tester.enterText(field, '6,19');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.submissions, hasLength(1));
      final sent = api.submissions.single;
      expect(sent.stationId, id);
      expect(sent.fuel, FuelType.pb95);
      expect(sent.price, 6.19);
      expect(find.text(S.fuelSubmitted), findsOneWidget);
    });

    testWidgets('LPG submissions go through with an LPG price', (tester) async {
      final api = _FakeApi();
      await _pumpFuel(tester, api: api);
      await tester.tap(find.byKey(const ValueKey('fuel-update-nowohucka-71')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fuel-form-price')),
        '3.19',
      );
      await tester.tap(find.byKey(const ValueKey('fuel-form-submit')));
      await tester.pumpAndSettle();
      expect(api.submissions.single.fuel, FuelType.lpg);
      expect(api.submissions.single.price, 3.19);
    });

    testWidgets('server outcomes map to messages', (tester) async {
      final api = _FakeApi(outcome: SubmitOutcome.rateLimited);
      await _pumpFuel(tester, api: api);
      Future<void> send() async {
        await tester.tap(
          find.byKey(const ValueKey('fuel-update-nowohucka-71')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('fuel-form-price')),
          '3.20',
        );
        await tester.tap(find.byKey(const ValueKey('fuel-form-submit')));
        await tester.pumpAndSettle();
      }

      await send();
      expect(find.text(S.fuelSubmitRateLimited), findsOneWidget);
      api.outcome = SubmitOutcome.failed;
      await send();
      expect(find.text(S.fuelSubmitFailed), findsOneWidget);
    });

    testWidgets('no LPG choice for a station that does not sell it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = _FakeApi();
      await tester.pumpWidget(
        MaterialApp(
          home: FuelScreen(
            api: api,
            initialTab: FuelTab.stations,
            saveReceipt: (_) async => 1,
            loadReceipts: () async => const [],
            stations: [stationById('wloczkow')!],
            locator: _FakeLocator(const LocationResult.found(_nearPilotow)),
            openUrl: (_) async => true,
            now: () => _now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No LPG'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fuel-update-wloczkow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fuel-form-lpg')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('fuel-form-price')),
        '6.39',
      );
      await tester.tap(find.byKey(const ValueKey('fuel-form-submit')));
      await tester.pumpAndSettle();
      expect(api.submissions.single.fuel, FuelType.pb95);
    });

    testWidgets('without ORLEN_API_URL: no refresh, no submissions', (
      tester,
    ) async {
      await _pumpFuel(tester);
      expect(find.text(S.fuelNotConfigured), findsOneWidget);
      expect(find.byKey(const ValueKey('fuel-refresh')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('fuel-update-nowohucka-71')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fuel-form-price')), findsNothing);
      expect(find.text(S.fuelNotConfigured), findsNWidgets(2));
    });

    testWidgets('fetch failure falls back to cached prices', (tester) async {
      await FuelPriceCache.write(
        _samplePrices,
        _now.subtract(const Duration(hours: 3)),
      );
      await _pumpFuel(tester, api: _FakeApi(failFetch: true));
      expect(
        find.text('Could not refresh prices. · Prices fetched 3 hours ago'),
        findsOneWidget,
      );
      expect(_cardOrder(tester).first, 'centralna-62');
    });

    testWidgets('refresh button fetches again', (tester) async {
      final api = _FakeApi();
      await _pumpFuel(tester, api: api);
      api.book = _samplePrices;
      await tester.tap(find.byKey(const ValueKey('fuel-refresh')));
      await tester.pumpAndSettle();
      expect(api.fetches, 2);
      expect(_cardOrder(tester).first, 'centralna-62');
    });

    testWidgets('Polish strings', (tester) async {
      S.setLang(AppLang.pl);
      await _pumpFuel(tester, api: _FakeApi(book: _samplePrices));
      expect(find.text('Paliwo'), findsOneWidget);
      expect(find.text('Stacje'), findsOneWidget);
      expect(find.text('Najtańsze'), findsOneWidget);
      expect(find.text('Najbliższe'), findsOneWidget);
      expect(find.text('2 godz. temu'), findsWidgets);
      expect(find.text('Nawiguj'), findsWidgets);
    });

    for (final lang in AppLang.values) {
      testWidgets('no overflow at 320 dp in ${lang.name}', (tester) async {
        S.setLang(lang);
        await _pumpFuel(
          tester,
          api: _FakeApi(book: _samplePrices),
          size: const Size(320, 640),
        );
        await tester.tap(find.byKey(const ValueKey('fuel-sort-nearest')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(ValueKey('fuel-update-${_cardOrder(tester).first}')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('stale prices are amber, only the hero says cheapest', (
      tester,
    ) async {
      await _pumpFuel(
        tester,
        api: _FakeApi(
          book: {
            ..._samplePrices,
            'sliwiaka-34': StationPrices(
              pb95: _price(6.19, age: const Duration(days: 2)),
              lpg: _price(3.29),
            ),
          },
        ),
      );
      final staleAge = tester.widget<Text>(find.text('2 days ago'));
      expect(staleAge.style?.color, AppColors.amber);
      expect(find.textContaining('CHEAPEST'), findsOneWidget);
    });
  });

  group('Fuel hub tabs', () {
    testWidgets('opens on Add fuel and switches to Stations', (tester) async {
      await _pumpFuel(
        tester,
        api: _FakeApi(book: _samplePrices),
        initialTab: FuelTab.add,
      );
      expect(find.byKey(const ValueKey('fuel-add-amount')), findsOneWidget);
      expect(find.byKey(const ValueKey('fuel-sort-cheapest')), findsNothing);
      expect(find.text(S.noFuelReceipts), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('fuel-tab-stations')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fuel-sort-cheapest')), findsOneWidget);
      expect(_cardOrder(tester).first, 'centralna-62');
    });

    testWidgets('opening Add fuel does not focus the amount field', (
      tester,
    ) async {
      await _pumpFuel(tester, initialTab: FuelTab.add);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
    });

    testWidgets('amount tap opens the keyboard; tab switch closes it', (
      tester,
    ) async {
      await _pumpFuel(tester, initialTab: FuelTab.add, api: _FakeApi());
      final amount = find.byKey(const ValueKey('fuel-add-amount'));

      await tester.tap(amount);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.enterText(amount, '120');
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('fuel-tab-stations')));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);

      // Coming back keeps the entry and does not pop the keyboard back up.
      await tester.tap(find.byKey(const ValueKey('fuel-tab-add')));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.widget<TextField>(amount).controller?.text, '120');
    });

    testWidgets('quick amount saves a receipt and lists it', (tester) async {
      final store = _FakeReceipts();
      await _pumpFuel(tester, initialTab: FuelTab.add, receipts: store);
      final submit = find.byKey(const ValueKey('fuel-add-submit'));
      expect(find.text(S.add), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('fuel-add-quick-100')));
      await tester.pump();
      expect(find.text(S.fuelAddButton(formatPln(100))), findsOneWidget);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(store.saved, [100]);
      expect(
        find.text(S.fuelAddedConfirmation(formatPln(100), 1)),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fuel-add-week-summary')),
        findsOneWidget,
      );
      expect(find.text('${formatPln(100)} PLN'), findsOneWidget);
      expect(find.text(S.add), findsOneWidget);
    });

    testWidgets('split saves only the driver share', (tester) async {
      final store = _FakeReceipts();
      await _pumpFuel(tester, initialTab: FuelTab.add, receipts: store);
      await tester.enterText(
        find.byKey(const ValueKey('fuel-add-amount')),
        '150',
      );
      await tester.tap(find.byKey(const ValueKey('fuel-add-split')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fuel-add-people-plus')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('fuel-add-people'))).data,
        '3',
      );
      expect(find.text(S.fuelSplitYourShare(formatPln(50))), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('fuel-add-submit')));
      await tester.pumpAndSettle();
      expect(store.saved, [50]);
    });

    for (final lang in AppLang.values) {
      testWidgets('Add fuel fits 320 dp in ${lang.name}', (tester) async {
        S.setLang(lang);
        await _pumpFuel(
          tester,
          initialTab: FuelTab.add,
          size: const Size(320, 640),
          receipts: _FakeReceipts([
            FuelReceipt(timestamp: _now, amountPaid: 1234.56),
          ]),
        );
        await tester.tap(find.byKey(const ValueKey('fuel-add-split')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('FuelReceiptStore', () {
    test('adds to the current week and reads it back', () async {
      final monday = DateTime(2026, 10, 12, 9);
      expect(await FuelReceiptStore.currentWeek(now: monday), isEmpty);
      expect(await FuelReceiptStore.add(120.5, now: monday), 1);
      expect(
        await FuelReceiptStore.add(
          80,
          now: monday.add(const Duration(days: 2)),
        ),
        2,
      );
      final week = await FuelReceiptStore.currentWeek(now: monday);
      expect([for (final r in week) r.amountPaid], [120.5, 80]);
      expect(
        await FuelReceiptStore.currentWeek(
          now: monday.add(const Duration(days: 7)),
        ),
        isEmpty,
      );
    });
  });

  testWidgets('Settings has a fuel prices row that opens the screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final snapshot = ValueNotifier(SettingsSnapshot.initial);
    addTearDown(snapshot.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          bindings: SettingsBindings(
            snapshot: snapshot,
            versionLabel: () => '5.0.4',
            setAutoComplete: (_) async {},
            setSteeringWheel: (_) async {},
            setKeepScreenOn: (_) async {},
            setAutoUpdate: (_) async {},
            setAutoEvents: (_) async {},
            setPillOrientation: (PillOrientation _) async {},
            setOverlayCancel: (_) async {},
            setNotificationControls: (_) async {},
            setHidePill: (_) async {},
            setLanguage: (_) async {},
            onDriverModeChanged: () {},
          ),
        ),
      ),
    );
    final row = find.byKey(const ValueKey('settings-fuel-prices'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(S.fuelEntryHint), findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(FuelScreen), findsOneWidget);
    expect(find.text(S.fuelNotConfigured), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
