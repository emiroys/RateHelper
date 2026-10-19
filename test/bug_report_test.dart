import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/bug_report_sheet.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:rate_helper/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleDiagnostics = BugReportDiagnostics(
    appVersion: '5.0.4+9',
    deviceModel: 'Samsung SM-S918B',
    androidVersion: 'Android 14 (SDK 34)',
    language: 'tr',
    pillOrientation: 'vertical',
    showOverlayCancel: true,
    notificationControls: true,
    hidePill: false,
    steeringWheel: true,
    autoComplete: false,
    keepScreenOn: true,
  );

  const sampleSnapshot = SettingsSnapshot(
    autoComplete: false,
    steeringWheel: true,
    keepScreenOn: true,
    autoUpdate: false,
    autoEvents: false,
    pillOrientation: PillOrientation.vertical,
    showOverlayCancel: true,
    notificationControls: true,
    hidePill: false,
    lang: AppLang.tr,
  );

  final fixedTime = DateTime.utc(2026, 10, 19, 18, 30, 0);

  setUp(() {
    S.setLang(AppLang.tr);
  });

  tearDown(() {
    S.setLang(AppLang.tr);
  });

  group('BugReportSanitizer — privacy and secret filtering', () {
    test('redacts URLs, endpoints, emails, tokens, and hashes', () {
      const raw =
          'GET https://gist.githubusercontent.com/user/abc123def456/raw/events.json?token=super_secret_999 '
          'Worker wss://fuel-worker.example.workers.dev/v1/stations '
          'Contact dev@example.com '
          'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.secret '
          'api_key=sk_live_987654321 '
          'bot 123456789:AAHfiqksKZ8WmR2z991234567890abcdef '
          'sha256 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

      final sanitized = BugReportSanitizer.sanitizeText(raw);

      expect(sanitized, isNot(contains('gist.githubusercontent.com')));
      expect(sanitized, isNot(contains('super_secret_999')));
      expect(sanitized, isNot(contains('fuel-worker.example.workers.dev')));
      expect(sanitized, isNot(contains('dev@example.com')));
      expect(
        sanitized,
        isNot(contains('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9')),
      );
      expect(sanitized, isNot(contains('sk_live_987654321')));
      expect(sanitized, isNot(contains('AAHfiqksKZ8WmR2z991234567890abcdef')));
      expect(
        sanitized,
        isNot(
          contains(
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          ),
        ),
      );

      expect(sanitized, contains('[REDACTED_URL]'));
      expect(sanitized, contains('[REDACTED_EMAIL]'));
      expect(sanitized, contains('[REDACTED_SECRET]'));
      expect(sanitized, contains('[REDACTED_HASH]'));
    });

    test(
      'redacts local file paths, phone numbers, GPS coordinates, and PLN/earnings amounts while preserving package: frames',
      () {
        const raw =
            'FileSystemException at /data/user/0/com.ratehelper.app/app_flutter/crash.log '
            'and C:\\Users\\driver\\Documents\\backup.json '
            'at package:rate_helper/home_screen.dart:142:7 '
            'Phone +48 512 345 678 or 48512345678 '
            'Location lat: 50.0647, lng=19.9450 '
            'Earnings 1924.50 PLN, 450 zł, netIncome: 3200.75, cashReceived=510';

        final sanitized = BugReportSanitizer.sanitizeText(raw);

        expect(sanitized, isNot(contains('/data/user/0/com.ratehelper.app')));
        expect(sanitized, isNot(contains(r'C:\Users\driver')));
        expect(sanitized, isNot(contains('512 345 678')));
        expect(sanitized, isNot(contains('48512345678')));
        expect(sanitized, isNot(contains('50.0647')));
        expect(sanitized, isNot(contains('19.9450')));
        expect(sanitized, isNot(contains('1924.50 PLN')));
        expect(sanitized, isNot(contains('450 zł')));
        expect(sanitized, isNot(contains('3200.75')));
        expect(sanitized, isNot(contains('cashReceived=510')));

        // Dart package stack frames must remain readable for debugging.
        expect(
          sanitized,
          contains('package:rate_helper/home_screen.dart:142:7'),
        );
        expect(sanitized, contains('[REDACTED_PATH]'));
        expect(sanitized, contains('[REDACTED_PHONE]'));
        expect(sanitized, contains('[REDACTED_LOCATION]'));
        expect(sanitized, contains('[REDACTED_AMOUNT]'));
      },
    );

    test(
      'sanitizeCrashLogExcerpt keeps only last 5 entries and enforces character cap',
      () {
        final buf = StringBuffer();
        for (var i = 1; i <= 8; i++) {
          buf
            ..writeln('--- [2026-10-19T12:0$i:00.000Z] [ERR_$i] ---')
            ..writeln(
              'Error #$i at /data/user/0/com.ratehelper.app/files/secret_$i.json',
            )
            ..writeln('Stack line for entry #$i')
            ..writeln();
        }

        final excerpt = BugReportSanitizer.sanitizeCrashLogExcerpt(
          buf.toString(),
        );

        // Entries 1..3 must be dropped; entries 4..8 must be present.
        expect(excerpt, isNot(contains('[ERR_1]')));
        expect(excerpt, isNot(contains('[ERR_2]')));
        expect(excerpt, isNot(contains('[ERR_3]')));
        expect(excerpt, contains('[ERR_4]'));
        expect(excerpt, contains('[ERR_8]'));
        expect(excerpt, isNot(contains('/data/user/0')));
        expect(excerpt, contains('[REDACTED_PATH]'));

        // Verify character cap truncation.
        final capped = BugReportSanitizer.sanitizeCrashLogExcerpt(
          buf.toString(),
          maxChars: 120,
        );
        expect(capped.startsWith('...\n'), isTrue);
        expect(capped.length, lessThanOrEqualTo(120));
      },
    );
  });

  group('BugReportSheet UI, localization, preview, and direct sending', () {
    Future<void> openSheet(
      WidgetTester tester, {
      BugScreenshotPicker? pickScreenshot,
      BugCrashLogLoader? loadCrashLog,
      BugDiagnosticsLoader? loadDiagnostics,
      BugReportSubmitter? submitReport,
      SettingsSnapshot snapshot = sampleSnapshot,
    }) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open-sheet'),
                onPressed: () {
                  showBugReportSheet(
                    context,
                    snapshot: snapshot,
                    versionLabel: '5.0.4+9',
                    pickScreenshot:
                        pickScreenshot ??
                        () async => const BugScreenshotPickResult.cancelled(),
                    loadCrashLog: loadCrashLog ?? () async => '',
                    loadDiagnostics:
                        loadDiagnostics ??
                        (snap, ver) async => sampleDiagnostics,
                    submitReport:
                        submitReport ??
                        (_) async => BugReportSubmitOutcome.sent,
                    now: fixedTime,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-sheet')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'supports TR, EN, and PL localized labels and all 5 categories',
      (tester) async {
        for (final lang in AppLang.values) {
          S.setLang(lang);
          expect(S.reportProblem, isNotEmpty);
          expect(S.reportCatOverlay, isNotEmpty);
          expect(S.reportCatCounters, isNotEmpty);
          expect(S.reportCatEarningsFuel, isNotEmpty);
          expect(S.reportCatSteeringNotification, isNotEmpty);
          expect(S.reportCatOther, isNotEmpty);
        }
        S.setLang(AppLang.tr);
        expect(S.reportSendAction, 'Raporu Gönder');
        S.setLang(AppLang.en);
        expect(S.reportSendAction, 'Send Report');
        S.setLang(AppLang.pl);
        expect(S.reportSendAction, 'Wyślij zgłoszenie');

        await openSheet(
          tester,
          snapshot: const SettingsSnapshot(
            autoComplete: false,
            steeringWheel: false,
            keepScreenOn: false,
            autoUpdate: false,
            autoEvents: false,
            pillOrientation: PillOrientation.horizontal,
            showOverlayCancel: false,
            notificationControls: false,
            hidePill: false,
            lang: AppLang.pl,
          ),
        );

        expect(find.text('Zgłoś problem'), findsOneWidget);
        expect(find.text('Liczniki'), findsOneWidget);
        expect(find.text('Wyślij zgłoszenie'), findsOneWidget);
        expect(find.textContaining('Telegram'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('bug-category-steeringNotification')),
        );
        await tester.pump();

        final preview = tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('bug-report-preview-text')),
            )
            .data!;
        expect(
          preview,
          contains(
            'Category: Kierownica / Powiadomienia (steeringNotification)',
          ),
        );
      },
    );

    testWidgets(
      'requires a description and sends the typed schema only after a tap',
      (tester) async {
        var submitCallCount = 0;
        BugReportSubmission? submitted;

        await openSheet(
          tester,
          submitReport: (submission) async {
            submitCallCount++;
            submitted = submission;
            return BugReportSubmitOutcome.sent;
          },
        );

        expect(submitCallCount, 0);
        final sendBtn = find.byKey(const ValueKey('bug-report-send-button'));
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pump();

        expect(submitCallCount, 0);
        expect(find.text(S.reportDescriptionEmptyError), findsOneWidget);

        // Enter description and select Counters category.
        await tester.tap(find.byKey(const ValueKey('bug-category-counters')));
        await tester.pump();

        const userDesc = 'Kabul sayacı vardiyada iki kez arttı.';
        await tester.enterText(
          find.byKey(const ValueKey('bug-report-description')),
          userDesc,
        );
        await tester.pump();

        expect(find.text(S.reportDescriptionEmptyError), findsNothing);

        final previewText = tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('bug-report-preview-text')),
            )
            .data!;
        expect(previewText, contains(userDesc));
        expect(previewText, contains('Category: Sayaçlar (counters)'));

        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(submitCallCount, 1);
        expect(submitted!.category, 'counters');
        expect(submitted!.description, userDesc);
        expect(submitted!.reportedAt, fixedTime);
        expect(submitted!.diagnostics, sampleDiagnostics);
        expect(find.text(S.reportSendSuccess), findsOneWidget);
        expect(
          find.byKey(const ValueKey('bug-report-description')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'diagnostics switch is ON by default and excludes device/app diagnostics when toggled OFF',
      (tester) async {
        BugReportSubmission? submitted;

        await openSheet(
          tester,
          submitReport: (submission) async {
            submitted = submission;
            return BugReportSubmitOutcome.failed;
          },
        );

        await tester.enterText(
          find.byKey(const ValueKey('bug-report-description')),
          'Overlay test',
        );
        await tester.pump();

        // Diagnostics ON by default.
        var previewText = tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('bug-report-preview-text')),
            )
            .data!;
        expect(previewText, contains('App Version: 5.0.4+9'));
        expect(previewText, contains('Device: Samsung SM-S918B'));
        expect(previewText, contains('Android: Android 14 (SDK 34)'));
        expect(previewText, contains('Overlay Orientation: vertical'));

        // Toggle diagnostics OFF.
        final diagSwitch = find.byKey(
          const ValueKey('bug-report-diagnostics-switch'),
        );
        await tester.ensureVisible(diagSwitch);
        await tester.tap(diagSwitch);
        await tester.pump();

        previewText = tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('bug-report-preview-text')),
            )
            .data!;
        expect(previewText, isNot(contains('Samsung SM-S918B')));
        expect(previewText, isNot(contains('Android 14')));
        expect(previewText, contains('Excluded by user.'));

        final sendBtn = find.byKey(const ValueKey('bug-report-send-button'));
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pump();

        expect(submitted, isNotNull);
        expect(submitted!.diagnostics, isNull);
      },
    );

    testWidgets(
      'crash logs switch is OFF by default and includes sanitized excerpt only when toggled ON',
      (tester) async {
        var crashLoaderCalls = 0;
        BugReportSubmission? submitted;
        const rawCrash =
            '--- [2026-10-19T15:00:00.000Z] [OVERLAY] ---\n'
            'Failed calling https://secret.example.com/api?token=abc999\n'
            'File: /data/user/0/com.ratehelper.app/app_flutter/crash.log\n'
            'at package:rate_helper/overlay_widget.dart:88:12';

        await openSheet(
          tester,
          loadCrashLog: () async {
            crashLoaderCalls++;
            return rawCrash;
          },
          submitReport: (submission) async {
            submitted = submission;
            return BugReportSubmitOutcome.failed;
          },
        );

        // Verify switch is OFF by default and crash log file was not even read yet.
        final crashSwitch = find.byKey(
          const ValueKey('bug-report-crash-logs-switch'),
        );
        expect(tester.widget<Switch>(crashSwitch).value, isFalse);
        expect(crashLoaderCalls, 0);

        var previewText = tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('bug-report-preview-text')),
            )
            .data!;
        expect(previewText, isNot(contains('Recent Error Logs')));
        expect(previewText, isNot(contains('overlay_widget.dart')));

        // Toggle crash logs ON.
        await tester.ensureVisible(crashSwitch);
        await tester.tap(crashSwitch);
        await tester.pumpAndSettle();

        expect(crashLoaderCalls, 1);
        previewText = tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('bug-report-preview-text')),
            )
            .data!;
        expect(previewText, contains('--- Recent Error Logs (Sanitized) ---'));
        expect(
          previewText,
          contains('package:rate_helper/overlay_widget.dart:88:12'),
        );
        expect(previewText, isNot(contains('secret.example.com')));
        expect(previewText, isNot(contains('abc999')));
        expect(previewText, isNot(contains('/data/user/0')));
        expect(previewText, contains('[REDACTED_URL]'));
        expect(previewText, contains('[REDACTED_PATH]'));

        await tester.enterText(
          find.byKey(const ValueKey('bug-report-description')),
          'Crash log test',
        );
        await tester.pump();
        final sendBtn = find.byKey(const ValueKey('bug-report-send-button'));
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pump();
        expect(submitted!.crashLog, contains('[REDACTED_URL]'));
        expect(submitted!.crashLog, contains('[REDACTED_PATH]'));
        expect(submitted!.crashLog, isNot(contains('secret.example.com')));
      },
    );

    testWidgets(
      'screenshot attachment is opt-in, removable, and passed to submitter',
      (tester) async {
        var nextPickResult = const BugScreenshotPickResult.tooLarge();
        BugScreenshotAttachment? submittedAttachment;

        await openSheet(
          tester,
          pickScreenshot: () async => nextPickResult,
          submitReport: (submission) async {
            submittedAttachment = submission.screenshot;
            return BugReportSubmitOutcome.failed;
          },
        );

        // 1. First attempt: too_large -> shows error message, no attachment added.
        final attachBtn = find.byKey(
          const ValueKey('bug-report-attach-screenshot'),
        );
        await tester.ensureVisible(attachBtn);
        await tester.tap(attachBtn);
        await tester.pump();

        expect(find.text(S.reportScreenshotTooLarge), findsOneWidget);
        expect(
          find.byKey(const ValueKey('bug-report-remove-screenshot')),
          findsNothing,
        );

        // 2. Second attempt: valid screenshot selected.
        nextPickResult = const BugScreenshotPickResult.ok(
          BugScreenshotAttachment(
            path: '/tmp/bug_screenshot.png',
            name: 'screen_01.png',
          ),
        );
        await tester.tap(attachBtn);
        await tester.pump();

        expect(find.text('screen_01.png'), findsOneWidget);
        var previewText = tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('bug-report-preview-text')),
            )
            .data!;
        expect(previewText, contains('Screenshot: screen_01.png'));

        // Enter description and send -> attachment is passed to submitter.
        await tester.enterText(
          find.byKey(const ValueKey('bug-report-description')),
          'Ekran görüntüsü testi',
        );
        await tester.pump();

        final sendBtn = find.byKey(const ValueKey('bug-report-send-button'));
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pump();

        expect(submittedAttachment, isNotNull);
        expect(submittedAttachment!.name, 'screen_01.png');

        // 3. Remove screenshot -> removed from UI and preview.
        final removeBtn = find.byKey(
          const ValueKey('bug-report-remove-screenshot'),
        );
        await tester.ensureVisible(removeBtn);
        await tester.tap(removeBtn);
        await tester.pump();

        expect(find.text('screen_01.png'), findsNothing);
        previewText = tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('bug-report-preview-text')),
            )
            .data!;
        expect(previewText, isNot(contains('Screenshot: screen_01.png')));
      },
    );

    testWidgets(
      'failure preserves form and attachment while a later success closes it',
      (tester) async {
        var statusToReturn = BugReportSubmitOutcome.failed;
        const attachment = BugScreenshotAttachment(
          path: '/tmp/bug_screenshot.png',
          name: 'failure.png',
        );

        await openSheet(
          tester,
          pickScreenshot: () async =>
              const BugScreenshotPickResult.ok(attachment),
          submitReport: (_) async => statusToReturn,
        );

        final attachBtn = find.byKey(
          const ValueKey('bug-report-attach-screenshot'),
        );
        await tester.ensureVisible(attachBtn);
        await tester.tap(attachBtn);
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('bug-report-description')),
          'Gönderim hata testi',
        );
        await tester.pump();

        final sendBtn = find.byKey(const ValueKey('bug-report-send-button'));
        await tester.ensureVisible(sendBtn);
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('bug-report-description')),
          findsOneWidget,
        );
        expect(find.text('Gönderim hata testi'), findsWidgets);
        expect(find.text('failure.png'), findsOneWidget);
        expect(find.text(S.reportSendFailed), findsOneWidget);

        statusToReturn = BugReportSubmitOutcome.sent;
        await tester.tap(sendBtn);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('bug-report-description')),
          findsNothing,
        );
      },
    );

    testWidgets('loading state blocks rapid duplicate submissions', (
      tester,
    ) async {
      final completer = Completer<BugReportSubmitOutcome>();
      var calls = 0;
      await openSheet(
        tester,
        submitReport: (_) {
          calls++;
          return completer.future;
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('bug-report-description')),
        'Duplicate tap test',
      );
      final sendBtn = find.byKey(const ValueKey('bug-report-send-button'));
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pump();
      await tester.tap(sendBtn);
      await tester.pump();

      expect(calls, 1);
      expect(find.text(S.reportSending), findsOneWidget);
      expect(tester.widget<FilledButton>(sendBtn).onPressed, isNull);

      completer.complete(BugReportSubmitOutcome.rateLimited);
      await tester.pumpAndSettle();
      expect(find.text(S.reportSendRateLimited), findsOneWidget);
      expect(find.text('Duplicate tap test'), findsWidgets);
    });
  });
}
