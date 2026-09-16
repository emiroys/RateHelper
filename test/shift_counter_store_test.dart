import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/shift_counter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  late File file;
  late ShiftCounterStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('shift_counters_');
    file = File('${tmp.path}${Platform.pathSeparator}shift_counters.json');
    store = ShiftCounterStore(file: file);
    ShiftCounterStore.resetInstanceForTest(file: file);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    ShiftCounterStore.resetInstanceForTest();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('write then read returns the same four counters', () async {
    await store.write(
      const ShiftCounters(
        accepted: 12,
        rejected: 3,
        completed: 8,
        canceled: 1,
      ),
    );
    expect(
      await store.read(),
      const ShiftCounters(
        accepted: 12,
        rejected: 3,
        completed: 8,
        canceled: 1,
      ),
    );
  });

  test('merge updates a subset without clobbering canceled', () async {
    await store.write(
      const ShiftCounters(
        accepted: 10,
        rejected: 2,
        completed: 7,
        canceled: 4,
      ),
    );
    final merged = await store.merge(accepted: 11, rejected: 2, completed: 8);
    expect(merged.accepted, 11);
    expect(merged.completed, 8);
    expect(merged.canceled, 4);
    expect((await store.read()).canceled, 4);
  });

  test('applyDelta adds signed deltas to what is on disk', () async {
    await store.write(
      const ShiftCounters(accepted: 10, rejected: 2, completed: 7, canceled: 4),
    );

    final next = await store.applyDelta(
      acceptedDelta: 3,
      rejectedDelta: -1,
      canceledDelta: 1,
    );

    expect(next.accepted, 13);
    expect(next.rejected, 1);
    expect(next.completed, 7);
    expect(next.canceled, 5);
    expect(await store.read(), next);
  });

  test('applyDelta clamps at zero and at the cap', () async {
    await store.write(const ShiftCounters(accepted: 2));

    expect((await store.applyDelta(acceptedDelta: -10)).accepted, 0);
    expect((await store.applyDelta(acceptedDelta: 5, max: 3)).accepted, 3);
  });

  test('concurrent applyDelta calls do not lose increments', () async {
    await store.write(const ShiftCounters());

    // Interleaved read-modify-write is exactly the overlay-vs-home race:
    // each call must see the previous one's result, never a stale snapshot.
    await Future.wait([
      for (var i = 0; i < 20; i++) store.applyDelta(acceptedDelta: 1),
    ]);

    expect((await store.read()).accepted, 20);
  });

  test('migrates legacy prefs ints then removes the keys', () async {
    SharedPreferences.setMockInitialValues({
      ShiftCounterStore.prefsKeyAccepted: 20,
      ShiftCounterStore.prefsKeyRejected: 5,
      ShiftCounterStore.prefsKeyCompleted: 14,
      ShiftCounterStore.prefsKeyCanceled: 2,
    });
    final prefs = await SharedPreferences.getInstance();

    await store.migrateFromPrefs(prefs);

    for (final key in ShiftCounterStore.prefsKeys) {
      expect(prefs.containsKey(key), isFalse);
    }
    expect(
      await store.read(),
      const ShiftCounters(
        accepted: 20,
        rejected: 5,
        completed: 14,
        canceled: 2,
      ),
    );
  });

  test('migrate is a no-op when the file already exists', () async {
    await store.write(
      const ShiftCounters(accepted: 9, rejected: 1, completed: 6, canceled: 0),
    );
    SharedPreferences.setMockInitialValues({
      ShiftCounterStore.prefsKeyAccepted: 99,
    });
    final prefs = await SharedPreferences.getInstance();

    await store.migrateFromPrefs(prefs);

    expect(prefs.containsKey(ShiftCounterStore.prefsKeyAccepted), isFalse);
    expect((await store.read()).accepted, 9);
  });

  test('a failed write does not kill subsequent queued writes', () async {
    await store.write(
      const ShiftCounters(accepted: 1, rejected: 0, completed: 0, canceled: 0),
    );

    await file.delete();
    await Directory(file.path).create();
    try {
      await store.write(
        const ShiftCounters(
          accepted: 2,
          rejected: 0,
          completed: 0,
          canceled: 0,
        ),
      );
    } catch (_) {}
    await Directory(file.path).delete(recursive: true);

    await store.write(
      const ShiftCounters(accepted: 3, rejected: 0, completed: 0, canceled: 0),
    );
    expect((await store.read()).accepted, 3);
  });
}
