import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/app_colors.dart';
import 'package:rate_helper/earnings_screen.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/onboarding_screen.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:rate_helper/radar_screen.dart';
import 'package:rate_helper/services/event_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Narrowest phone we realistically support. Polish is the longest of the three
/// languages, so anything that fits here fits everywhere.
const _narrow = Size(320, 640);

/// Nominal Galaxy S24 Ultra logical size.
const _target = Size(384, 832);

void _stubChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void stub(String name, Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => handler(call),
    );
  }

  stub('com.ratehelper.app/system', (call) {
    switch (call.method) {
      case 'manufacturer':
        return 'samsung';
      case 'isIgnoringBatteryOptimizations':
      case 'isAccessibilityServiceEnabled':
        return false;
      default:
        return null;
    }
  });
  stub('x-slayer/overlay_channel', (_) => false);
  stub('x-slayer/overlay_messenger', (_) => null);
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  Widget child,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    _stubChannels();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => S.setLang(AppLang.tr));

  group('no layout overflow in any supported language', () {
    for (final lang in AppLang.values) {
      for (final size in [_narrow, _target]) {
        final label = '${lang.name} @ ${size.width.toInt()}dp';

        testWidgets('EarningsScreen renders clean — $label', (tester) async {
          S.setLang(lang);
          await _pumpAt(tester, size, const EarningsScreen());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });

        testWidgets('EarningsScreen entry form renders clean — $label',
            (tester) async {
          S.setLang(lang);
          await _pumpAt(tester, size, const EarningsScreen(autoAddWeek: true));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });

        testWidgets('OnboardingScreen renders clean — $label', (tester) async {
          S.setLang(lang);
          await _pumpAt(tester, size, OnboardingScreen(onDone: () {}));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });

        // Covers the shimmer skeleton and, once the fetch has exhausted its
        // one 2s retry, the offline error state.
        testWidgets('RadarScreen renders clean — $label', (tester) async {
          S.setLang(lang);
          EventService.clearCache();
          await _pumpAt(tester, size, const RadarScreen());
          expect(tester.takeException(), isNull, reason: 'loading skeleton');
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'error state');
        });

        testWidgets('OverlayWidget pill renders clean — $label',
            (tester) async {
          S.setLang(lang);
          await _pumpAt(tester, size, const OverlayWidget());
          await tester.pump();
          expect(tester.takeException(), isNull);
        });

        testWidgets('keep-screen-on switch renders clean — $label',
            (tester) async {
          S.setLang(lang);
          await _pumpAt(
            tester,
            size,
            Scaffold(
              backgroundColor: Colors.black,
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        S.keepScreenOn,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    Switch(value: false, onChanged: (_) {}),
                  ],
                ),
              ),
            ),
          );
          expect(find.text(S.keepScreenOn), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('pill orientation row renders clean — $label',
            (tester) async {
          S.setLang(lang);
          await _pumpAt(
            tester,
            size,
            Scaffold(
              backgroundColor: Colors.black,
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Text(
                      S.overlayPillOrientation,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(child: Text(S.overlayPillHorizontal)),
                        Expanded(child: Text(S.overlayPillVertical)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
          expect(find.text(S.overlayPillOrientation), findsOneWidget);
          expect(find.text(S.overlayPillHorizontal), findsOneWidget);
          expect(find.text(S.overlayPillVertical), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('earnings empty states are designed, not blank', () {
    testWidgets('shows an icon, copy and a call to action with no data',
        (tester) async {
      S.setLang(AppLang.pl);
      await _pumpAt(tester, _target, const EarningsScreen());
      await tester.pumpAndSettle();

      expect(find.text(S.noEarnings), findsOneWidget);
      expect(find.text(S.addWeek), findsOneWidget);
      expect(find.byIcon(Icons.savings_rounded), findsOneWidget);

      // The history header must not appear alongside the empty card — that
      // duplicated the same "nothing here" message twice.
      expect(find.text(S.history), findsNothing);
    });
  });

  group('semantic palette is shared, not re-declared', () {
    test('threshold triad has the expected canonical values', () {
      expect(AppColors.emerald, const Color(0xFF10B981));
      expect(AppColors.crimson, const Color(0xFFEF4444));
      expect(AppColors.amber, const Color(0xFFF59E0B));
      expect(AppColors.recordGold, const Color(0xFFFFD54A));
      expect(AppColors.gold, const Color(0xFFFFD54A));
      expect(AppColors.actionAccent, const Color(0xFF38BDF8));
    });

    test('surface tokens match the consolidated 3-tone system', () {
      expect(AppColors.background, const Color(0xFF0D0D0D));
      expect(AppColors.surface, const Color(0xFF161616));
      expect(AppColors.surfaceElevated, const Color(0xFF1E1E1E));
      expect(AppColors.card, AppColors.surface);
      expect(AppColors.sheet, AppColors.surface);
      expect(AppColors.dialog, AppColors.surface);
      expect(AppColors.elevated, AppColors.surfaceElevated);
    });

    test('label colors clear the dim-text threshold used before', () {
      // Old values were white38 (0x61) / white24 (0x3D); anything at or below
      // that is hard to read in direct sunlight.
      expect(AppColors.labelText.a, greaterThan(0.61));
      expect(AppColors.mutedText.a, greaterThan(0.55));
      expect(AppColors.disabledText.a, greaterThan(0.24));
    });
  });
}
