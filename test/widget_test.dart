import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/earnings_screen.dart';
import 'package:rate_helper/main.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const RateHelperApp(showOnboarding: false));
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
}


