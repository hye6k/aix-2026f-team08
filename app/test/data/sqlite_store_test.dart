import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:morning_routine/data/sqlite_store.dart';
import 'package:morning_routine/data/snapshot_codec.dart';
import 'package:morning_routine/domain/models.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String file;
  late SqliteRoutineStore store;
  final at = DateTime.utc(2026, 10, 31, 7, 0, 0, 0, 123);
  final routine = Routine(
    id: "r'; DROP TABLE settings; --",
    name: '등교',
    steps: [
      RoutineStep(id: 'z', name: '세면', expected: const Duration(minutes: 10)),
      RoutineStep(id: 'a', name: '식사', expected: const Duration(minutes: 20)),
    ],
  );
  final settings = AppSettings(
    arrivalTime: ClockTime(9, 0),
    travelDuration: const Duration(minutes: 40),
    sleepDuration: const Duration(hours: 8),
    wakeMode: WakeMode.manual,
    manualWakeTime: ClockTime(7, 0),
    detectionStart: ClockTime(23, 0),
    detectionEnd: ClockTime(9, 0),
  );
  RoutineRun run({int revision = 0, RunStatus status = RunStatus.running}) =>
      RoutineRun(
        id: 'run',
        routineId: routine.id,
        routineName: routine.name,
        startedAt: at,
        updatedAt: at.add(Duration(minutes: revision)),
        revision: revision,
        status: status,
        endedAt: status == RunStatus.running
            ? null
            : at.add(Duration(minutes: revision)),
        steps: [
          StepExecution(
            step: routine.steps.first,
            status: status == RunStatus.running
                ? StepStatus.active
                : StepStatus.interrupted,
            startedAt: at,
            endedAt: status == RunStatus.running
                ? null
                : at.add(Duration(minutes: revision)),
          ),
          StepExecution(step: routine.steps.last, status: StepStatus.pending),
        ],
      );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('morning-store-');
    file = '${directory.path}/store.db';
    store = await SqliteRoutineStore.open(file, factory: databaseFactoryFfi);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('빈 DB의 결과를 명시한다', () async {
    expect(await store.loadSettings(), isNull);
    expect(await store.listRoutines(), isEmpty);
    expect(await store.listWakeRecords(), isEmpty);
    expect(await store.listRuns(), isEmpty);
  });
  test('파일을 닫고 다시 열어 모든 설정·순서·상태·마이크로초를 복원한다', () async {
    await store.saveSettings(settings);
    await store.saveRoutine(routine);
    await store.saveWakeRecord(
      WakeRecord(
        id: 'w',
        observedAt: at,
        source: WakeSource.screenOn,
        status: WakeStatus.pending,
      ),
    );
    await store.saveRun(run());
    await store.close();
    store = await SqliteRoutineStore.open(file, factory: databaseFactoryFfi);
    final restoredSettings = (await store.loadSettings())!;
    expect(restoredSettings.wakeMode, WakeMode.manual);
    expect(restoredSettings.manualWakeTime, ClockTime(7, 0));
    expect(restoredSettings.detectionStart, ClockTime(23, 0));
    expect(restoredSettings.travelDuration, const Duration(minutes: 40));
    expect((await store.listRoutines()).single.steps.map((s) => s.id), [
      'z',
      'a',
    ]);
    expect((await store.listWakeRecords()).single.status, WakeStatus.pending);
    final restored = (await store.listRuns()).single;
    expect(restored.startedAt, at);
    expect(restored.activeStep!.step.id, 'z');
    expect(restored.wakeRecordId, isNull);
  });
  test('루틴 수정·삭제가 과거 실행 단계 스냅샷을 변경하지 않는다', () async {
    await store.saveRoutine(routine);
    await store.saveRun(run());
    await store.saveRoutine(
      Routine(
        id: routine.id,
        name: '변경',
        steps: [
          RoutineStep(
            id: 'new',
            name: '새 단계',
            expected: const Duration(minutes: 1),
          ),
        ],
      ),
    );
    expect((await store.listRoutines()).single.name, '변경');
    await store.deleteRoutine(routine.id);
    expect(await store.listRoutines(), isEmpty);
    expect((await store.listRuns()).single.steps.first.step.name, '세면');
  });
  test('후보 저장은 멱등적이며 확정 기록을 미확인으로 되돌리지 않는다', () async {
    final pending = WakeRecord(
      id: 'w',
      observedAt: at,
      source: WakeSource.screenOn,
      status: WakeStatus.pending,
    );
    final confirmed = WakeRecord(
      id: 'w',
      observedAt: at,
      source: WakeSource.screenOn,
      status: WakeStatus.confirmed,
      decidedAt: at,
      wakeAt: at,
    );
    await store.saveWakeRecord(pending);
    await store.saveWakeRecord(pending);
    await store.saveWakeRecord(confirmed);
    await expectLater(store.saveWakeRecord(pending), throwsStateError);
    expect((await store.listWakeRecords()).single.status, WakeStatus.confirmed);
    await store.close();
    store = await SqliteRoutineStore.open(file, factory: databaseFactoryFfi);
    expect((await store.listWakeRecords()).single.status, WakeStatus.confirmed);
  });
  test('오래된 실행 저장을 롤백하고 종료 상태의 재실행을 막는다', () async {
    await store.saveRun(run());
    await store.saveRun(run());
    await store.saveRun(run(revision: 1));
    await expectLater(store.saveRun(run()), throwsStateError);
    expect((await store.listRuns()).single.revision, 1);
    await store.saveRun(run(revision: 2, status: RunStatus.stopped));
    await expectLater(store.saveRun(run(revision: 3)), throwsStateError);
    expect((await store.listRuns()).single.status, RunStatus.stopped);
  });
  test('손상·미지원 저장 형식은 조용히 초기화하지 않고 오류를 반환한다', () async {
    await store.saveSettings(settings);
    final db = await databaseFactoryFfi.openDatabase(file);
    await db.update(
      'settings',
      {'payload': '{"schema":999}'},
      where: 'id = ?',
      whereArgs: [1],
    );
    await expectLater(store.loadSettings(), throwsFormatException);
    expect(
      () => const SnapshotCodec().decodeRoutine('{'),
      throwsFormatException,
    );
  });
}
