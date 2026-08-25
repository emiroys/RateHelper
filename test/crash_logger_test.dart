import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/crash_logger.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('crash_log_');
    file = File('${tmp.path}${Platform.pathSeparator}crash.log');
    CrashLogger.debugReset(file: file);
  });

  tearDown(() async {
    CrashLogger.debugReset();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('rate-limits a burst to 5 writes plus a dropped summary', () async {
    for (var i = 0; i < 20; i++) {
      await CrashLogger.appendError('T', 'msg $i', null, null);
    }

    int headerCount(String body) =>
        RegExp(r'^--- ', multiLine: true).allMatches(body).length;

    final first = await file.readAsString();
    expect(headerCount(first), 5);
    expect(first.contains('dropped'), isFalse);

    await CrashLogger.flushDroppedSummaryForTest();

    final later = await file.readAsString();
    expect(later.contains('[RATE_LIMIT]'), isTrue);
    expect(later.contains('dropped 15'), isTrue);
    expect(headerCount(later), 6);
  });
}
