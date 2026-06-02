import 'package:flutter_test/flutter_test.dart';
import 'package:ubertakip/main.dart';

void main() {
  testWidgets('App boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const UberTakipApp(showOnboarding: false));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
