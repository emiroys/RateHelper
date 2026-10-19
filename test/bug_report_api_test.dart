import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/bug_report_api.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const diagnostics = BugReportDiagnostics(
    appVersion: '5.0.4+9',
    deviceModel: 'Samsung SM-S928B',
    androidVersion: 'Android 15 (SDK 35)',
    language: 'tr',
    pillOrientation: 'horizontal',
    showOverlayCancel: true,
    notificationControls: true,
    hidePill: false,
    steeringWheel: true,
    autoComplete: false,
    keepScreenOn: true,
  );
  final reportedAt = DateTime.utc(2026, 10, 19, 12);

  BugReportSubmission submission({BugScreenshotAttachment? screenshot}) =>
      BugReportSubmission(
        category: 'overlay',
        description: 'Cancel button changed the overlay layout.',
        reportedAt: reportedAt,
        diagnostics: diagnostics,
        crashLog: 'sanitized log',
        screenshot: screenshot,
      );

  test('configuration accepts only a secure Worker base URL', () {
    expect(BugReportApi.fromConfig(''), isNull);
    expect(BugReportApi.fromConfig('mock'), isNull);
    expect(BugReportApi.fromConfig('http://worker.example'), isNull);
    expect(BugReportApi.fromConfig('https://u:p@worker.example'), isNull);
    expect(BugReportApi.fromConfig('https://worker.example?q=1'), isNull);
    expect(
      BugReportApi.fromConfig('https://worker.example/api/'),
      isA<HttpBugReportApi>(),
    );
  });

  group('HttpBugReportApi multipart delivery', () {
    late HttpServer server;
    late Directory tempDir;
    late List<int> receivedBody;
    late HttpHeaders receivedHeaders;
    var responseStatus = HttpStatus.created;

    setUp(() async {
      receivedBody = [];
      responseStatus = HttpStatus.created;
      tempDir = await Directory.systemTemp.createTemp('ratehelper-bug-test-');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        receivedHeaders = request.headers;
        receivedBody = await request.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        request.response
          ..statusCode = responseStatus
          ..headers.contentType = ContentType.json
          ..write('{}');
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await tempDir.delete(recursive: true);
    });

    Future<BugReportSubmitOutcome> send(BugReportSubmission report) {
      return HttpOverrides.runWithHttpOverrides(() {
        final api = HttpBugReportApi(
          Uri.parse('http://127.0.0.1:${server.port}/api'),
        );
        return api.submit(report);
      }, _RealHttp());
    }

    test(
      'successful text report uses fixed schema and leaks no bot config',
      () async {
        expect(await send(submission()), BugReportSubmitOutcome.sent);
        expect(receivedHeaders.contentType!.mimeType, 'multipart/form-data');
        final body = utf8.decode(receivedBody, allowMalformed: true);
        expect(body, contains('name="payload"'));
        expect(body, contains('"schemaVersion":1'));
        expect(body, contains('"category":"overlay"'));
        expect(body, isNot(contains('name="screenshot"')));
        expect(body, isNot(contains('TELEGRAM_BOT_TOKEN')));
        expect(body, isNot(contains('TELEGRAM_ADMIN_CHAT_ID')));
        expect(body, isNot(contains('"chat_id"')));
      },
    );

    test('report with a validated PNG is uploaded as one screenshot', () async {
      final image = File('${tempDir.path}${Platform.pathSeparator}screen.png');
      await image.writeAsBytes(const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        1,
        2,
        3,
      ]);
      final report = submission(
        screenshot: BugScreenshotAttachment(
          path: image.path,
          name: 'chosen-name.png',
        ),
      );

      expect(await send(report), BugReportSubmitOutcome.sent);
      final body = utf8.decode(receivedBody, allowMalformed: true);
      expect(body, contains('name="screenshot"; filename="screenshot.png"'));
      expect(body, contains('Content-Type: image/png'));
    });

    test(
      'rejects invalid and oversized screenshot before network delivery',
      () async {
        final invalid = File('${tempDir.path}${Platform.pathSeparator}bad.png');
        await invalid.writeAsBytes(const [1, 2, 3]);
        expect(
          await send(
            submission(
              screenshot: BugScreenshotAttachment(
                path: invalid.path,
                name: 'bad.png',
              ),
            ),
          ),
          BugReportSubmitOutcome.invalid,
        );
        expect(receivedBody, isEmpty);

        final oversized = File(
          '${tempDir.path}${Platform.pathSeparator}big.png',
        );
        await oversized.writeAsBytes(
          List<int>.filled(maxBugScreenshotBytes + 1, 0),
        );
        expect(
          await send(
            submission(
              screenshot: BugScreenshotAttachment(
                path: oversized.path,
                name: 'big.png',
              ),
            ),
          ),
          BugReportSubmitOutcome.tooLarge,
        );
        expect(receivedBody, isEmpty);
      },
    );

    test(
      'maps duplicate, rate-limit, and Telegram failure responses',
      () async {
        responseStatus = HttpStatus.conflict;
        expect(await send(submission()), BugReportSubmitOutcome.duplicate);
        responseStatus = HttpStatus.tooManyRequests;
        expect(await send(submission()), BugReportSubmitOutcome.rateLimited);
        responseStatus = HttpStatus.badGateway;
        expect(await send(submission()), BugReportSubmitOutcome.failed);
      },
    );
  });
}
