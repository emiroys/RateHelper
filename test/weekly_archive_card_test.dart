import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/app_colors.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/models/weekly_archive_entry.dart';
import 'package:rate_helper/weekly_archive_card.dart';

void main() {
  const floors = [
    WeeklyGoalFloor(name: 'tier0', minTrips: 0, acceptRate: null),
    WeeklyGoalFloor(name: 'tier1', minTrips: 100, acceptRate: 80),
    WeeklyGoalFloor(name: 'tier2', minTrips: 150, acceptRate: 70),
  ];

  tearDown(() => S.setLang(AppLang.tr));

  Future<void> pumpCard(WidgetTester tester, WeeklyArchiveEntry entry) async {
    S.setLang(AppLang.tr);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyArchiveCard(
            entry: entry,
            floors: floors,
            fallbackTier: 'tier1',
            fallbackAcceptRate: 80,
          ),
        ),
      ),
    );
  }

  Color badgeColor(WidgetTester tester, String label) {
    return tester.widget<Text>(find.text(label)).style!.color!;
  }

  WeeklyArchiveEntry cardEntry({
    required double acceptRate,
    required double cancelRate,
    required double? target,
    double maxCancel = kWeeklyCancelCeiling,
    int completed = 102,
    int canceled = 4,
    int accepted = 106,
    int rejected = 26,
  }) {
    return WeeklyArchiveEntry(
      weekStart: DateTime(2026, 9, 7),
      weekEnd: DateTime(2026, 9, 13),
      acceptRate: acceptRate,
      cancelRate: cancelRate,
      acceptedCount: accepted,
      rejectedCount: rejected,
      completedTrips: completed,
      canceledTrips: canceled,
      canceledTripsStored: true,
      goalTier: 'tier1',
      targetAcceptRate: target,
      targetAcceptRateStored: true,
      maxCancelRate: maxCancel,
    );
  }

  testWidgets('weekly badges show one decimal place', (tester) async {
    await pumpCard(
      tester,
      cardEntry(acceptRate: 80.34, cancelRate: 3.76, target: 80),
    );

    expect(find.text('%80.3 Kabul'), findsOneWidget);
    expect(find.text('%3.8 İptal'), findsOneWidget);
    expect(find.text('%80 Kabul'), findsNothing);
    expect(find.text('%4 İptal'), findsNothing);
  });

  testWidgets('badge colors follow the saved goal, not a fixed 80%', (
    tester,
  ) async {
    await pumpCard(
      tester,
      cardEntry(acceptRate: 75, cancelRate: 6, target: 70, maxCancel: 10),
    );

    // 75 would be red under a hardcoded 80, and 6 would be red under a
    // hardcoded 5. Both are inside this week's own thresholds.
    expect(badgeColor(tester, '%75.0 Kabul'), AppColors.emerald);
    expect(badgeColor(tester, '%6.0 İptal'), AppColors.emerald);

    await pumpCard(
      tester,
      cardEntry(acceptRate: 85, cancelRate: 5.1, target: 90),
    );

    // 85 would be green under a hardcoded 80. This week's target is 90.
    expect(badgeColor(tester, '%85.0 Kabul'), AppColors.crimson);
    expect(badgeColor(tester, '%5.1 İptal'), AppColors.crimson);
  });

  testWidgets('tapping a weekly card expands and collapses the trip counts', (
    tester,
  ) async {
    await pumpCard(
      tester,
      cardEntry(acceptRate: 80.3, cancelRate: 3.8, target: 80),
    );

    expect(find.text('Yolculuk: 102 • Kabul: 106 • Red: 26'), findsOneWidget);
    expect(find.text(S.archiveCompletedTrips), findsNothing);
    expect(find.text(S.archiveCancelledTrips), findsNothing);

    await tester.tap(find.byType(WeeklyArchiveCard));
    await tester.pumpAndSettle();

    expect(find.text(S.archiveCompletedTrips), findsOneWidget);
    expect(find.text('102'), findsOneWidget);
    expect(find.text(S.archiveCancelledTrips), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text(S.archiveAcceptedRequests), findsOneWidget);
    expect(find.text(S.archiveRejectedRequests), findsOneWidget);
    expect(find.text(S.archiveTotalRequests), findsOneWidget);
    expect(find.text('132'), findsOneWidget);
    expect(find.textContaining('Hedef Tuttu'), findsOneWidget);

    await tester.tap(find.byType(WeeklyArchiveCard));
    await tester.pumpAndSettle();

    expect(find.text(S.archiveCompletedTrips), findsNothing);
    expect(find.text(S.archiveCancelledTrips), findsNothing);
    expect(find.text('102'), findsNothing);
    expect(find.text('Yolculuk: 102 • Kabul: 106 • Red: 26'), findsOneWidget);
  });
}
