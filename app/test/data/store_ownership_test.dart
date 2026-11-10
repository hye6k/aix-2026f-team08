import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/data/sqlite_store.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/ports.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  final opened = <RoutineStore>[];
  final settings = AppSettings(
    arrivalTime: ClockTime(9, 0),
    travelDuration: const Duration(minutes: 30),
    sleepDuration: const Duration(hours: 8),
    wakeMode: WakeMode.recommended,
    detectionStart: ClockTime(6, 0),
    detectionEnd: ClockTime(9, 0),
  );
  Future<RoutineStore> open(String name) async {
    final store = await SqliteRoutineStore.open(
      '${dir.path}/$name.db',
      factory: databaseFactoryFfi,
    );
    opened.add(store);
    return store;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ownership-');
  });
  tearDown(() async {
    for (final store in opened.reversed) {
      await store.close();
    }
    opened.clear();
    await dir.delete(recursive: true);
  });

  test('같은 파일의 별도 wrapper는 독립 수명이 아니며 한쪽 종료가 다른 쪽에도 적용된다', () async {
    final ownerA = await open('shared');
    final wrapperB = await open('shared');
    expect(identical(ownerA, wrapperB), isFalse);
    await ownerA.saveSettings(settings);
    expect((await wrapperB.loadSettings())!.arrivalTime, ClockTime(9, 0));
    await ownerA.close();
    await expectLater(
      wrapperB.loadSettings(),
      throwsA(
        predicate<Object>((e) => e.toString().contains('database_closed')),
      ),
    );
  });

  test('다른 DB 파일은 한 파일의 소유자가 종료해도 계속 사용할 수 있다', () async {
    final first = await open('first');
    final second = await open('second');
    await first.saveSettings(settings);
    expect(await second.loadSettings(), isNull);
    await first.close();
    await second.saveSettings(settings);
    expect(
      (await second.loadSettings())!.travelDuration,
      const Duration(minutes: 30),
    );
  });

  test('소유 저장소를 소비자에 공유하고 마지막에 닫은 뒤 재개방해도 저장값이 유지된다', () async {
    final owner = await open('application');
    final RoutineStore settingsConsumer = owner;
    final RoutineStore routineConsumer = owner;
    await settingsConsumer.saveSettings(settings);
    final routine = Routine(
      id: 'r',
      name: '등교',
      steps: [
        RoutineStep(
          id: 'wash',
          name: '세면',
          expected: const Duration(minutes: 10),
        ),
      ],
    );
    await routineConsumer.saveRoutine(routine);
    expect((await settingsConsumer.listRoutines()).single.id, 'r');
    expect(
      (await routineConsumer.loadSettings())!.arrivalTime,
      ClockTime(9, 0),
    );
    // 화면별 close 없이 소비자 작업 완료 후 소유자가 종료한다.
    await owner.close();
    final reopenedOwner = await open('application');
    expect((await reopenedOwner.listRoutines()).single.steps.single.id, 'wash');
    expect(
      (await reopenedOwner.loadSettings())!.sleepDuration,
      const Duration(hours: 8),
    );
  });
}
