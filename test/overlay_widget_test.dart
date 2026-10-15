import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/app_colors.dart';
import 'package:rate_helper/app_spacing.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:rate_helper/shift_counter_store.dart';
import 'package:rate_helper/tap_history_store.dart';
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

  test('cancel-to-reject gap stays at least AppSpacing.sm', () {
    expect(OverlayWidget.cancelGapDp, greaterThanOrEqualTo(AppSpacing.sm));
    expect(OverlayWidget.verticalGapDp, AppSpacing.sm);
    expect(OverlayWidget.cancelBtnSizeDp, greaterThanOrEqualTo(48));
    expect(OverlayWidget.btnSizeDp, greaterThanOrEqualTo(48));
  });

  for (final orientation in PillOrientation.values) {
    testWidgets(
      '${orientation.name} pill orders cancel, reject, rate, accept',
      (tester) async {
        final sep = Platform.pathSeparator;
        final tmp = Directory(
          '${Directory.systemTemp.path}$sep'
          'overlay_order_${orientation.name}_${DateTime.now().microsecondsSinceEpoch}',
        );
        tmp.createSync(recursive: true);
        final countersFile = File('${tmp.path}${sep}shift_counters.json');
        ShiftCounterStore.resetInstanceForTest(file: countersFile);
        TapHistoryStore.resetInstanceForTest(
          file: File('${tmp.path}${sep}tap_history.jsonl'),
        );
        addTearDown(() {
          ShiftCounterStore.resetInstanceForTest();
          TapHistoryStore.resetInstanceForTest();
          S.setLang(AppLang.tr);
          try {
            if (tmp.existsSync()) tmp.deleteSync(recursive: true);
          } catch (_) {}
        });

        countersFile.writeAsStringSync(
          const ShiftCounters(accepted: 3, rejected: 1).encode(),
        );
        S.setLang(AppLang.en);
        SharedPreferences.setMockInitialValues({
          OverlayWidget.cancelButtonPrefsKey: true,
          PillOrientation.prefsKey: orientation.name,
          'appLanguage': 'en',
        });

        await tester.pumpWidget(
          MaterialApp(
            home: OverlayWidget(
              initialOrientation: orientation,
              initialShowCancel: true,
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        final rateFinder = find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data?.contains('%') ?? false),
        );
        expect(rateFinder, findsOneWidget);

        final vertical = orientation.isVertical;
        final rate = tester.getTopLeft(rateFinder);
        final cancel = tester.getTopLeft(find.byIcon(Icons.block_rounded));
        final reject = tester.getTopLeft(find.byIcon(Icons.remove_rounded));
        final accept = tester.getTopLeft(find.byIcon(Icons.add_rounded));
        if (vertical) {
          expect(cancel.dy, lessThan(reject.dy));
          expect(reject.dy, lessThan(rate.dy));
          expect(rate.dy, lessThan(accept.dy));
        } else {
          expect(cancel.dx, lessThan(reject.dx));
          expect(reject.dx, lessThan(rate.dx));
          expect(rate.dx, lessThan(accept.dx));
        }

        final cancelRect = _squareButtonRect(tester, Icons.block_rounded);
        final rejectRect = _squareButtonRect(tester, Icons.remove_rounded);
        final acceptRect = _squareButtonRect(tester, Icons.add_rounded);
        expect(cancelRect.shortestSide, OverlayWidget.cancelBtnSizeDp);
        expect(rejectRect.shortestSide, greaterThanOrEqualTo(48));
        expect(acceptRect.shortestSide, greaterThanOrEqualTo(48));
        final gap = vertical
            ? rejectRect.top - cancelRect.bottom
            : rejectRect.left - cancelRect.right;
        expect(gap, greaterThanOrEqualTo(AppSpacing.sm));

        final pill = tester.getRect(
          find.byWidgetPredicate(
            (w) =>
                w is SizedBox &&
                w.width ==
                    OverlayWidget.windowWidthDp(
                      orientation,
                      showCancel: true,
                    ).toDouble() &&
                w.height ==
                    OverlayWidget.windowHeightDp(
                      orientation,
                      showCancel: true,
                    ).toDouble(),
          ),
        );
        expect(pill.contains(cancelRect.center), isTrue);
        expect(pill.contains(rejectRect.center), isTrue);
        expect(pill.contains(acceptRect.center), isTrue);

        var sawSeed = false;
        for (var i = 0; i < 20 && !sawSeed; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          sawSeed = find.text('75%').evaluate().isNotEmpty;
        }
        expect(sawSeed, isTrue, reason: 'startup did not load the seeded 3/1 rate');

        Future<ShiftCounters> settleAndRead() async {
          await tester.pump(const Duration(milliseconds: 400));
          // Fake-async file writes complete one await per real-time gap.
          // Cancel persists as a second write after merge, so this has to
          // drain the queue before the file is read.
          for (var i = 0; i < 30; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          for (var attempt = 0; attempt < 6; attempt++) {
            try {
              return ShiftCounters.decode(countersFile.readAsStringSync());
            } on FileSystemException {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 40)),
              );
            }
          }
          return ShiftCounters.decode(countersFile.readAsStringSync());
        }

        await tester.tap(find.byIcon(Icons.remove_rounded));
        await tester.pump();
        expect(find.text('60%'), findsOneWidget);
        var stored = await settleAndRead();
        expect(stored.rejected, 2, reason: stored.encode());

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump();
        expect(find.text('66.7%'), findsOneWidget);
        stored = await settleAndRead();
        expect(stored.accepted, 4, reason: stored.encode());

        await tester.tap(find.byIcon(Icons.block_rounded));
        await tester.pump();
        expect(find.text('66.7%'), findsOneWidget);
        stored = await settleAndRead();
        expect(stored.canceled, 1, reason: stored.encode());
        expect(stored.accepted, 4, reason: stored.encode());
        expect(stored.rejected, 2, reason: stored.encode());
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  }

  for (final orientation in PillOrientation.values) {
    testWidgets(
      '${orientation.name} percentage is centred between − and + with room',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: OverlayWidget(initialOrientation: orientation)),
        );
        // Let the first-build _TapPop (1.14× → 1×) settle before measuring.
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);

        final vertical = orientation.isVertical;
        final pill = tester.getRect(
          find.byWidgetPredicate(
            (w) =>
                w is SizedBox &&
                w.width == OverlayWidget.windowWidthDp(orientation) &&
                w.height == OverlayWidget.windowHeightDp(orientation),
          ),
        );
        final reject = _squareButtonRect(tester, Icons.remove_rounded);
        final accept = _squareButtonRect(tester, Icons.add_rounded);
        final rateText = find.byWidgetPredicate(
          (w) => w is Text && (w.data?.contains('%') ?? false),
        );
        final rate = tester.getRect(rateText);

        // Dead centre of the capsule, equal gaps to − and +.
        expect(rate.center.dx, moreOrLessEquals(pill.center.dx, epsilon: 0.5));
        expect(rate.center.dy, moreOrLessEquals(pill.center.dy, epsilon: 0.5));
        final slot = tester.getRect(
          find.ancestor(of: rateText, matching: find.byType(InkWell)),
        );
        final before = vertical
            ? slot.top - reject.bottom
            : slot.left - reject.right;
        final after = vertical
            ? accept.top - slot.bottom
            : accept.left - slot.right;
        expect(before, moreOrLessEquals(after, epsilon: 0.5));

        // getRect is in global space, so it already includes the FittedBox
        // scale-down: these are the painted glyph bounds.
        expect(rate.left - pill.left, greaterThanOrEqualTo(AppSpacing.sm));
        expect(pill.right - rate.right, greaterThanOrEqualTo(AppSpacing.sm));
      },
    );
  }

  group('collapse to bubble', _collapseTests);
}

void _collapseTests() {
  late List<MethodCall> resizeCalls;
  late Future<Object?> Function(MethodCall call) onResize;
  late Directory tmp;

  setUp(() {
    resizeCalls = [];
    onResize = (_) async => true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('x-slayer/overlay'), (
          call,
        ) {
          if (call.method != 'resizeOverlay') return Future.value(true);
          resizeCalls.add(call);
          return onResize(call);
        });
    final sep = Platform.pathSeparator;
    tmp = Directory(
      '${Directory.systemTemp.path}${sep}overlay_collapse_'
      '${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    ShiftCounterStore.resetInstanceForTest(
      file: File('${tmp.path}${sep}shift_counters.json'),
    );
    TapHistoryStore.resetInstanceForTest(
      file: File('${tmp.path}${sep}tap_history.jsonl'),
    );
  });

  tearDown(() {
    ShiftCounterStore.resetInstanceForTest();
    TapHistoryStore.resetInstanceForTest();
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Finder rateText() => find.byWidgetPredicate(
    (w) => w is Text && (w.data?.contains('%') ?? false),
  );
  Finder bubble() => find.text(S.overlayBubbleLetter);

  Map<Object?, Object?> sizeOf(MethodCall call) =>
      call.arguments as Map<Object?, Object?>;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('tapping the percentage collapses window and pill to the bubble',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OverlayWidget()));
    await tester.pump();

    await tester.tap(rateText());
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(bubble(), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(resizeCalls, hasLength(1));
    expect(sizeOf(resizeCalls.single), {'width': 48, 'height': 48});
    expect(
      tester.getRect(find.byType(InkWell)),
      const Rect.fromLTWH(
        0,
        0,
        OverlayWidget.bubbleSizeDp,
        OverlayWidget.bubbleSizeDp,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(OverlayWidget.collapsedPrefsKey), isTrue);
  });

  testWidgets('bubble is an opaque dark circle with a white R', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OverlayWidget(initialCollapsed: true)),
    );
    await settle(tester);

    final material = tester.widget<Material>(
      find.ancestor(of: bubble(), matching: find.byType(Material)).first,
    );
    expect(material.color, AppColors.surface);
    expect(material.color!.a, 1.0);
    final shape = material.shape! as CircleBorder;
    expect(shape.side.color, AppColors.strongBorder);
    expect(shape.side.width, inInclusiveRange(1.0, 1.5));
    final letter = tester.widget<Text>(bubble());
    expect(letter.style!.color, Colors.white);
    expect(letter.style!.fontWeight!.value, greaterThanOrEqualTo(700));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the bubble grows the window first, then shows the pill',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      OverlayWidget.collapsedPrefsKey: true,
    });
    await tester.pumpWidget(
      const MaterialApp(home: OverlayWidget(initialCollapsed: true)),
    );
    await settle(tester);
    // Startup shrinks the pill-sized window opened by home.
    expect(resizeCalls, hasLength(1));
    expect(sizeOf(resizeCalls.single), {'width': 48, 'height': 48});
    expect(bubble(), findsOneWidget);

    await tester.tap(bubble());
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(resizeCalls, hasLength(2));
    expect(sizeOf(resizeCalls.last), {
      'width': OverlayWidget.nativeWindowWidthDp,
      'height': OverlayWidget.nativeWindowHeightDp,
    });
    expect(bubble(), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(OverlayWidget.collapsedPrefsKey), isFalse);
  });

  testWidgets('vertical pill expands back to 74x194', (tester) async {
    SharedPreferences.setMockInitialValues({
      PillOrientation.prefsKey: PillOrientation.vertical.name,
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: OverlayWidget(initialOrientation: PillOrientation.vertical),
      ),
    );
    await tester.pump();
    await tester.tap(rateText());
    await settle(tester);
    await tester.tap(bubble());
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(sizeOf(resizeCalls.last), {'width': 74, 'height': 194});
    expect(find.byType(Column), findsWidgets);
  });

  testWidgets('a failed collapse resize keeps the pill', (tester) async {
    onResize = (_) async => false;
    await tester.pumpWidget(const MaterialApp(home: OverlayWidget()));
    await tester.pump();

    await tester.tap(rateText());
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(bubble(), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(OverlayWidget.collapsedPrefsKey), isNull);

    // Not frozen: the next tap tries again.
    onResize = (_) async => true;
    await tester.tap(rateText());
    await settle(tester);
    expect(bubble(), findsOneWidget);
  });

  testWidgets('a throwing expand resize keeps the bubble usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: OverlayWidget(initialCollapsed: true)),
    );
    await settle(tester);
    onResize = (_) async => throw PlatformException(code: 'boom');

    await tester.tap(bubble());
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(bubble(), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
  });

  testWidgets('taps while a resize is in flight are ignored', (tester) async {
    final pending = Completer<Object?>();
    await tester.pumpWidget(
      const MaterialApp(home: OverlayWidget(initialCollapsed: true)),
    );
    await settle(tester);
    onResize = (_) => pending.future;

    await tester.tap(bubble());
    await tester.pump();
    await tester.tap(bubble());
    await tester.pump();
    await tester.tap(bubble());
    await tester.pump();
    // One startup shrink + one expand; the extra taps were dropped.
    expect(resizeCalls, hasLength(2));

    pending.complete(true);
    await settle(tester);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('steering-wheel increments still count while collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: OverlayWidget(initialCollapsed: true)),
    );
    await settle(tester);

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'x-slayer/overlay_messenger',
      const JSONMessageCodec().encodeMessage(<String, Object>{
        'action': 'media_key_increment',
        'key': 'rejected',
      }),
      (_) {},
    );
    await tester.pump();
    expect(bubble(), findsOneWidget);

    await tester.tap(bubble());
    await settle(tester);
    expect(find.text(S.formatPercent('0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Rect _squareButtonRect(WidgetTester tester, IconData icon) {
  final iconElement = tester.element(find.byIcon(icon));
  SizedBox? box;
  iconElement.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is SizedBox &&
        widget.width != null &&
        widget.height != null &&
        widget.width == widget.height) {
      box = widget;
      return false;
    }
    return true;
  });
  expect(box, isNotNull);
  return tester.getRect(find.byWidget(box!));
}
