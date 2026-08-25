import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/tap_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  late File file;
  late TapHistoryStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tap_history_');
    file = File('${tmp.path}${Platform.pathSeparator}tap_history.jsonl');
    store = TapHistoryStore(file: file);
    TapHistoryStore.resetInstanceForTest(file: file);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    TapHistoryStore.resetInstanceForTest();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('append writes one NDJSON line per tap', () async {
    await store.append('accepted', at: DateTime(2026, 8, 25, 10, 5, 6));
    await store.append('rejected', at: DateTime(2026, 8, 25, 10, 5, 7));

    final lines = (await file.readAsString())
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    expect(lines, hasLength(2));

    final first = jsonDecode(lines[0]) as Map<String, dynamic>;
    expect(first['type'], 'accepted');
    expect(first['localTime'], '10:05:06');
    expect(first['timestamp'], isNotEmpty);

    final newestFirst = await store.readNewestFirst();
    expect(newestFirst, hasLength(2));
    expect(newestFirst.first['type'], 'rejected');
    expect(newestFirst.last['type'], 'accepted');
  });

  test('compacts to the last 500 entries', () async {
    for (var i = 0; i < TapHistoryStore.maxEntries + 3; i++) {
      await store.append(i.isEven ? 'accepted' : 'rejected');
    }

    final all = await store.readAll();
    expect(all, hasLength(TapHistoryStore.maxEntries));
    expect(all.first['type'], 'rejected');
    expect(all.last['type'], 'accepted');
  });

  test('migrates the old prefs JSON array then removes the key', () async {
    final legacy = [
      {
        'type': 'accepted',
        'timestamp': '2026-01-01T00:00:00.000',
        'localTime': '00:00:00',
      },
      {
        'type': 'rejected',
        'timestamp': '2026-01-01T00:00:01.000',
        'localTime': '00:00:01',
      },
    ];
    SharedPreferences.setMockInitialValues({
      TapHistoryStore.prefsKey: jsonEncode(legacy),
    });
    final prefs = await SharedPreferences.getInstance();

    await store.migrateFromPrefs(prefs);

    expect(prefs.containsKey(TapHistoryStore.prefsKey), isFalse);
    final all = await store.readAll();
    expect(all, hasLength(2));
    expect(all[0]['type'], 'accepted');
    expect(all[1]['type'], 'rejected');
  });

  test('clear truncates the file', () async {
    await store.append('accepted');
    await store.append('rejected');
    await store.clear();

    expect(await store.readAll(), isEmpty);
    expect((await file.readAsString()).trim(), isEmpty);
  });
}
