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
      OverlayWidget.verticalPillWidthDp.round(),
    );
    expect(
      OverlayWidget.windowHeightDp(PillOrientation.vertical),
      OverlayWidget.verticalPillHeightDp.round(),
    );
    expect(OverlayWidget.verticalPillWidthDp, 74);
    expect(
      OverlayWidget.verticalPillWidthDp,
      OverlayWidget.btnSizeDp + OverlayWidget.verticalInsetDp * 2,
    );
    // Portrait pill hugs its content — no dead space at the stadium caps.
    expect(
      OverlayWidget.verticalPillHeightDp,
      OverlayWidget.btnSizeDp * 2 +
          OverlayWidget.verticalGapDp * 2 +
          OverlayWidget.verticalRateSlotDp +
          OverlayWidget.verticalInsetDp * 2,
    );
    expect(PillOrientation.prefsKey, 'overlay_pill_orientation');
    expect(PillOrientation.fromName('vertical'), PillOrientation.vertical);
    expect(PillOrientation.fromName(null), PillOrientation.horizontal);
    expect(
      OverlayWidget.cancelButtonPrefsKey,
      'overlay_show_cancel_button',
    );
  });

  test('cancel button grows only the long axis of the window', () {
    expect(
      OverlayWidget.windowWidthDp(
        PillOrientation.horizontal,
        showCancel: true,
      ),
      (OverlayWidget.pillWidthDp +
              OverlayWidget.cancelGapDp +
              OverlayWidget.cancelBtnSizeDp)
          .round(),
    );
    expect(
      OverlayWidget.windowHeightDp(
        PillOrientation.horizontal,
        showCancel: true,
      ),
      OverlayWidget.pillHeightDp.round(),
    );
    expect(
      OverlayWidget.windowWidthDp(PillOrientation.vertical, showCancel: true),
      OverlayWidget.verticalPillWidthDp.round(),
    );
    expect(
      OverlayWidget.windowHeightDp(PillOrientation.vertical, showCancel: true),
      (OverlayWidget.verticalPillHeightDp +
              OverlayWidget.verticalGapDp +
              OverlayWidget.cancelBtnSizeDp)
          .round(),
    );
  });

  testWidgets('horizontal pill renders +/- buttons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OverlayWidget()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    expect(find.byIcon(Icons.block_rounded), findsNothing);
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

  testWidgets('vertical pill is 74x194 with a Column', (tester) async {
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
    expect(find.byIcon(Icons.block_rounded), findsNothing);
  });

  testWidgets('cancel button is a smaller amber control on the long axis', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      OverlayWidget.cancelButtonPrefsKey: true,
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: OverlayWidget(initialShowCancel: true),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SizedBox &&
            w.width ==
                OverlayWidget.windowWidthDp(
                  PillOrientation.horizontal,
                  showCancel: true,
                ).toDouble() &&
            w.height == OverlayWidget.pillHeightDp,
      ),
      findsOneWidget,
    );
  });

  testWidgets('vertical pill grows in height when cancel is enabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      OverlayWidget.cancelButtonPrefsKey: true,
      PillOrientation.prefsKey: PillOrientation.vertical.name,
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: OverlayWidget(
          initialOrientation: PillOrientation.vertical,
          initialShowCancel: true,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SizedBox &&
            w.width == OverlayWidget.verticalPillWidthDp &&
            w.height ==
                OverlayWidget.windowHeightDp(
                  PillOrientation.vertical,
                  showCancel: true,
                ).toDouble(),
      ),
      findsOneWidget,
    );
  });
}
