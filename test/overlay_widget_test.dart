import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _stubOverlayChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(
    const MethodChannel('x-slayer/overlay_channel'),
    (call) async => false,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('x-slayer/overlay'),
    (call) async => true,
  );
  messenger.setMockMessageHandler('x-slayer/overlay_messenger', (_) async {
    return null;
  });
}

void main() {
  setUp(() {
    _stubOverlayChannels();
    SharedPreferences.setMockInitialValues({});
  });

  test('window size swaps for the vertical pill', () {
    expect(
      OverlayWidget.windowWidthDp(PillOrientation.horizontal),
      OverlayWidget.nativeWindowWidthDp,
    );
    expect(
      OverlayWidget.windowHeightDp(PillOrientation.horizontal),
      OverlayWidget.nativeWindowHeightDp,
    );
    expect(
      OverlayWidget.windowWidthDp(PillOrientation.vertical),
      OverlayWidget.nativeWindowHeightDp,
    );
    expect(
      OverlayWidget.windowHeightDp(PillOrientation.vertical),
      OverlayWidget.nativeWindowWidthDp,
    );
    expect(PillOrientation.prefsKey, 'overlay_pill_orientation');
    expect(PillOrientation.fromName('vertical'), PillOrientation.vertical);
    expect(PillOrientation.fromName(null), PillOrientation.horizontal);
  });

  testWidgets('horizontal pill renders +/- buttons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OverlayWidget()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SizedBox &&
            w.width == OverlayWidget.pillWidthDp &&
            w.height == OverlayWidget.pillHeightDp,
      ),
      findsOneWidget,
    );
  });

  testWidgets('vertical pill is 80x276 with a Column', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OverlayWidget(initialOrientation: PillOrientation.vertical),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SizedBox &&
            w.width == OverlayWidget.verticalPillWidthDp &&
            w.height == OverlayWidget.verticalPillHeightDp,
      ),
      findsOneWidget,
    );
    expect(find.byType(Column), findsWidgets);
  });
}
