import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/app_widgets.dart';
import 'package:rate_helper/earnings_screen.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/main.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const RateHelperApp(showOnboarding: false));
    // First frame is before the shift is read: heroes must be skeletons, not
    // the `%100,00` / `0` snap that used to look like a wiped week.
    expect(find.byType(AppShimmer), findsWidgets);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('OverlayWidget boots and wraps static circular buttons in RepaintBoundary', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: OverlayWidget()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final repaintBoundaries = find.descendant(
      of: find.byType(OverlayWidget),
      matching: find.byType(RepaintBoundary),
    );
    expect(repaintBoundaries, findsAtLeastNWidgets(2));
  });

  testWidgets('EarningsScreen text fields have length limits and upper-bound range validation', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: EarningsScreen(autoAddWeek: true)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final textFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(textFields, isNotEmpty);
    for (final field in textFields) {
      final hasLengthLimiter = field.inputFormatters?.any((f) => f is LengthLimitingTextInputFormatter && f.maxLength == 7) ?? false;
      expect(hasLengthLimiter, isTrue, reason: 'Field should have LengthLimitingTextInputFormatter(7)');
    }

    final formFields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    for (final field in formFields) {
      if (field.validator != null) {
        expect(field.validator!('9999999'), isNotNull, reason: 'Should reject extreme numbers above 999999.0');
      }
    }
  });

  group('fuel split helper', () {
    tearDown(() => S.setLang(AppLang.tr));

    /// Opens the quick-add dialog at a narrow phone width. The returned list
    /// holds the amount the dialog pops with, once it closes.
    Future<List<double?>> openDialog(WidgetTester tester) async {
      S.setLang(AppLang.tr);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final result = <double?>[null];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result[0] = await showFuelAmountDialog(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return result;
    }

    testWidgets('saves the typed amount when split is off', (tester) async {
      final result = await openDialog(tester);
      expect(find.text(S.fuelSplitPeopleLabel), findsNothing);

      await tester.enterText(find.byType(TextField), '150');
      await tester.tap(find.text(S.add));
      await tester.pumpAndSettle();

      expect(result.single, 150);
      expect(tester.takeException(), isNull);
    });

    testWidgets('live-splits a full receipt and Kullan fills the share', (
      tester,
    ) async {
      final result = await openDialog(tester);

      await tester.tap(find.text(S.fuelSplitToggle));
      await tester.pumpAndSettle();
      expect(find.text(S.fuelSplitPeopleLabel), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), '150');
      await tester.pump();
      expect(find.text(S.fuelSplitYourShare('75,00')), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(find.text(S.fuelSplitYourShare('50,00')), findsOneWidget);

      await tester.tap(find.text(S.fuelSplitUse));
      await tester.pump();
      expect(find.text(S.fuelSplitPeopleLabel), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '50',
      );

      await tester.tap(find.text(S.add));
      await tester.pumpAndSettle();
      expect(result.single, 50);
    });

    testWidgets('Add commits the share while the helper is still open', (
      tester,
    ) async {
      final result = await openDialog(tester);
      await tester.enterText(find.byType(TextField), '150');
      await tester.tap(find.text(S.fuelSplitToggle));
      await tester.pump();
      expect(find.text(S.fuelSplitYourShare('75,00')), findsOneWidget);

      await tester.tap(find.text(S.add));
      await tester.pumpAndSettle();
      expect(result.single, 75);
    });

    testWidgets('people stepper stays inside 2–6', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text(S.fuelSplitToggle));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump();
      }
      expect(find.text('6'), findsOneWidget);
      expect(find.text('7'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('entry form receipt button opens the same split dialog', (
      tester,
    ) async {
      S.setLang(AppLang.tr);
      SharedPreferences.setMockInitialValues({'driver_mode_asked': true});
      await tester.pumpWidget(
        const MaterialApp(home: EarningsScreen(autoAddWeek: true)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final addReceipt = find.text(S.addReceipt);
      expect(addReceipt, findsWidgets);
      await tester.ensureVisible(addReceipt.first);
      await tester.tap(addReceipt.first);
      await tester.pumpAndSettle();

      expect(find.text(S.quickAddFuelTitle), findsOneWidget);
      expect(find.text(S.fuelSplitToggle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}


