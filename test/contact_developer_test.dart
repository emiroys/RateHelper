import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/contact_developer.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => S.setLang(AppLang.tr));

  group('whatsAppUrl', () {
    test('digits build a wa.me link with the encoded localized prefill', () {
      S.setLang(AppLang.tr);
      final url = ContactDeveloper.whatsAppUrl('48123456789')!;
      expect(url, startsWith('https://wa.me/48123456789?text='));
      final text = Uri.parse(url).queryParameters['text'];
      expect(text, 'Merhaba Emirhan, RateHelper hakkında yazıyorum: ');

      S.setLang(AppLang.pl);
      expect(
        Uri.parse(
          ContactDeveloper.whatsAppUrl('48123456789')!,
        ).queryParameters['text'],
        'Cześć Emirhan, piszę w sprawie aplikacji RateHelper: ',
      );
    });

    test('a full wa.me link (QR contact) is used as-is', () {
      expect(
        ContactDeveloper.whatsAppUrl(' https://wa.me/qr/ABC123 '),
        'https://wa.me/qr/ABC123',
      );
    });

    test('empty or malformed values fall back to nothing', () {
      expect(ContactDeveloper.whatsAppUrl(''), isNull);
      expect(ContactDeveloper.whatsAppUrl('+48 123 456 789'), isNull);
      expect(ContactDeveloper.whatsAppUrl('http://evil.example'), isNull);
    });

    test('public builds have no number and go to GitHub issues', () {
      expect(ContactDeveloper.whatsApp, isEmpty);
      expect(ContactDeveloper.targetUrl, ContactDeveloper.issuesUrl);
      expect(ContactDeveloper.subtitle, 'Emirhan Metin • GitHub');
    });
  });

  testWidgets('settings row shows the name and opens the link natively', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('com.ratehelper.app/system');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

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
            setPillOrientation: (_) async {},
            setOverlayCancel: (_) async {},
            setNotificationControls: (_) async {},
            setHidePill: (_) async {},
            setLanguage: (_) async {},
            onDriverModeChanged: () {},
          ),
        ),
      ),
    );

    final row = find.byKey(const ValueKey('settings-contact-developer'));
    await tester.scrollUntilVisible(
      row,
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.ensureVisible(row);
    await tester.pump();
    expect(find.text(S.contactDeveloper), findsOneWidget);
    expect(find.textContaining('Emirhan Metin'), findsOneWidget);

    await tester.tap(row);
    await tester.pump();

    final open = calls.where((c) => c.method == 'openExternalUrl').toList();
    expect(open, hasLength(1));
    expect((open.single.arguments as Map)['url'], ContactDeveloper.issuesUrl);
    expect(find.text(S.contactDeveloperFailed), findsNothing);
  });
}
