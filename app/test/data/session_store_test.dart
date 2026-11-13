import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:morning_routine/data/sqlite_store.dart';
import 'package:morning_routine/data/snapshot_codec.dart';
import 'package:morning_routine/application/session_port.dart';
import 'package:morning_routine/application/morning_session.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/ports.dart';

import '../application/morning_session_test.dart'
    show Platform, routine, settings;

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  late SqliteRoutineStore store;
  final day = DateTime.utc(2026, 11, 8);
  SessionCheckpoint checkpoint(
    int revision, {
    String? wakeId,
    String? runId,
    bool cancel = false,
  }) => SessionCheckpoint(
    revision: revision,
    routineId: 'r',
    arrivalDay: day,
    wakeId: wakeId,
    runId: runId,
    cancellationPending: cancel,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('session-');
    path = '${directory.path}/session.db';
    store = await SqliteRoutineStore.open(path, factory: databaseFactoryFfi);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  test('회차와 실제 파일을 재개방해 날짜·후보·실행을 복원한다', () async {
    final platform = Platform();
    var now = DateTime.utc(2026, 11, 8, 7);
    var id = 0;
    MorningSession session() => MorningSession(
      store: store,
      alarmPort: platform,
      signals: platform,
      clock: () => now,
      newId: () => 'record-${id++}',
    );
    var active = session();
    await active.initialize();
    await active.configure(
      settings: settings(),
      routine: routine(),
      arrivalDay: day,
    );
    await active.observe(ActivitySignal(at: now, source: WakeSource.screenOn));
    await active.startRoutine();
    final wakeId = active.view.wake!.id, runId = active.view.run!.id;
    await active.close();
    await store.close();
    store = await SqliteRoutineStore.open(path, factory: databaseFactoryFfi);
    now = now.add(const Duration(minutes: 30));
    active = session();
    await active.initialize();
    expect(active.view.wake!.id, wakeId);
    expect(active.view.run!.id, runId);
    expect(
      active.view.prediction!.remainingPreparation,
      const Duration(minutes: 11),
    );
    expect((await store.loadSession())!.arrivalDay, day);
    await active.stopRoutine();
    await active.close();
    await platform.input.close();
  });
  test('기록 저장 거부는 설정과 회차 갱신도 롤백한다', () async {
    final wake = WakeRecord(
      id: 'wake',
      observedAt: day,
      source: WakeSource.manual,
      status: WakeStatus.confirmed,
      decidedAt: day,
      wakeAt: day,
    );
    await store.commitSession(
      checkpoint(0, wakeId: 'wake'),
      settings: settings(),
      routine: routine(),
      wake: wake,
    );
    final changed = AppSettings(
      arrivalTime: ClockTime(10, 0),
      travelDuration: const Duration(minutes: 1),
      sleepDuration: const Duration(hours: 8),
      wakeMode: WakeMode.recommended,
      detectionStart: ClockTime(6, 0),
      detectionEnd: ClockTime(9, 0),
    );
    final invalid = WakeRecord(
      id: 'wake',
      observedAt: day,
      source: WakeSource.screenOn,
      status: WakeStatus.pending,
    );
    await expectLater(
      store.commitSession(
        checkpoint(1, wakeId: 'wake'),
        settings: changed,
        wake: invalid,
      ),
      throwsStateError,
    );
    expect((await store.loadSettings())!.arrivalTime, ClockTime(9, 0));
    expect((await store.loadSession())!.revision, 0);
    expect((await store.listWakeRecords()).single.status, WakeStatus.confirmed);
  });
  test('활성 참조 검증 실패 시 새 루틴도 저장되지 않는다', () async {
    await expectLater(
      store.commitSession(
        checkpoint(0, wakeId: 'missing'),
        settings: settings(),
        routine: routine(),
      ),
      throwsStateError,
    );
    expect(await store.loadSettings(), isNull);
    expect(await store.listRoutines(), isEmpty);
    expect(await store.loadSession(), isNull);
  });
  test('오래된 세션 쓰기는 설정을 덮어쓰지 않는다', () async {
    await store.commitSession(
      checkpoint(2),
      settings: settings(),
      routine: routine(),
    );
    await expectLater(store.commitSession(checkpoint(1)), throwsStateError);
    expect((await store.loadSession())!.revision, 2);
  });
  test('확정되지 않은 후보는 알람 취소 대기로 저장할 수 없다', () async {
    final wake = WakeRecord(
      id: 'wake',
      observedAt: day,
      source: WakeSource.screenOn,
      status: WakeStatus.pending,
    );
    await expectLater(
      store.commitSession(
        checkpoint(0, wakeId: 'wake', cancel: true),
        settings: settings(),
        routine: routine(),
        wake: wake,
      ),
      throwsStateError,
    );
    expect(await store.listWakeRecords(), isEmpty);
  });
  test('알람 적용 대기와 다시 울림 대상 시각을 파일 재개방해 보존한다', () async {
    final at = day.add(const Duration(hours: 7, minutes: 5));
    await store.commitSession(
      SessionCheckpoint(
        revision: 0,
        routineId: 'r',
        arrivalDay: day,
        alarmUpdatePending: true,
        alarmPendingAt: at,
      ),
      settings: settings(),
      routine: routine(),
    );
    await store.close();
    store = await SqliteRoutineStore.open(path, factory: databaseFactoryFfi);
    final loaded = (await store.loadSession())!;
    expect(loaded.alarmUpdatePending, isTrue);
    expect(loaded.alarmPendingAt, at);
  });
  test('활성 루틴 직접 삭제는 복원을 망가뜨리지 않고 거부한다', () async {
    await store.commitSession(
      checkpoint(0),
      settings: settings(),
      routine: routine(),
    );
    await expectLater(store.deleteRoutine('r'), throwsStateError);
    expect((await store.listRoutines()).single.id, 'r');
    expect((await store.loadSession())!.routineId, 'r');
  });
  test('활성 계획의 설정·루틴 직접 수정은 원자 세션 API로 유도한다', () async {
    await store.commitSession(
      checkpoint(0),
      settings: settings(),
      routine: routine(),
    );
    await expectLater(store.saveSettings(settings()), throwsStateError);
    await expectLater(store.saveRoutine(routine()), throwsStateError);
    expect((await store.loadSession())!.revision, 0);
  });
  test('예약 실패 회차를 실제 파일에서 복원해 같은 의도로 재시도한다', () async {
    final platform = Platform()..failSchedule = true;
    final now = day.add(const Duration(hours: 7));
    MorningSession make() => MorningSession(
      store: store,
      alarmPort: platform,
      signals: platform,
      clock: () => now,
      newId: () => 'id',
    );
    var active = make();
    await active.initialize();
    await expectLater(
      active.configure(
        settings: settings(),
        routine: routine(),
        arrivalDay: day,
      ),
      throwsStateError,
    );
    await active.close();
    await store.close();
    store = await SqliteRoutineStore.open(path, factory: databaseFactoryFfi);
    active = make();
    await active.initialize();
    expect(active.view.alarmUpdatePending, isTrue);
    platform.failSchedule = false;
    await active.retryAlarm();
    expect(active.view.alarmUpdatePending, isFalse);
    expect(platform.scheduled.single.at, DateTime.utc(2026, 11, 8, 8, 10));
    await active.close();
    await platform.input.close();
  });
  test('알람 대기 필드가 없는 이전 v2 회차도 읽을 수 있다', () async {
    await store.saveSettings(settings());
    await store.saveRoutine(routine());
    final raw = await databaseFactoryFfi.openDatabase(path);
    await raw.insert('session_context', {
      'id': 1,
      'revision': 0,
      'payload': '{"version":1,"routineId":"r","day":[2026,11,8],"utc":true,"wakeId":null,"runId":null,"cancellationPending":false}',
    });
    await store.close();
    store = await SqliteRoutineStore.open(path, factory: databaseFactoryFfi);
    final restored = (await store.loadSession())!;
    expect(restored.alarmUpdatePending, isFalse);
    expect(restored.alarmPendingAt, isNull);
  });
  test('기존 v1 파일의 설정·루틴·기상·실행과 인덱스를 보존한다', () async {
    await store.close();
    await File(path).delete();
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE settings (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE routines (id TEXT PRIMARY KEY, name TEXT NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE wake_records (id TEXT PRIMARY KEY, observed_at INTEGER NOT NULL, status TEXT NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE routine_runs (id TEXT PRIMARY KEY, started_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, status TEXT NOT NULL, revision INTEGER NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX wake_time ON wake_records(observed_at DESC)',
          );
          await db.execute(
            'CREATE INDEX run_status_time ON routine_runs(status,started_at DESC)',
          );
        },
      ),
    );
    const codec = SnapshotCodec();
    final wake = WakeRecord(
      id: 'legacy-w',
      observedAt: day,
      source: WakeSource.screenOn,
      status: WakeStatus.pending,
    );
    await legacy.insert('settings', {
      'id': 1,
      'payload': codec.encodeSettings(settings()),
    });
    await legacy.insert('routines', {
      'id': 'r',
      'name': '아침',
      'payload': codec.encodeRoutine(routine()),
    });
    await legacy.insert('wake_records', {
      'id': wake.id,
      'observed_at': day.microsecondsSinceEpoch,
      'status': 'pending',
      'payload': codec.encodeWake(wake),
    });
    final run = RoutineRun(
      id: 'legacy-run',
      routineId: 'r',
      routineName: '아침',
      startedAt: day,
      updatedAt: day,
      status: RunStatus.running,
      steps: [
        StepExecution(
          step: routine().steps[0],
          status: StepStatus.active,
          startedAt: day,
        ),
        StepExecution(step: routine().steps[1], status: StepStatus.pending),
      ],
    );
    await legacy.insert('routine_runs', {
      'id': run.id,
      'started_at': day.microsecondsSinceEpoch,
      'updated_at': day.microsecondsSinceEpoch,
      'status': 'running',
      'revision': 0,
      'payload': codec.encodeRun(run),
    });
    await legacy.close();
    store = await SqliteRoutineStore.open(path, factory: databaseFactoryFfi);
    expect(await store.loadSettings(), isNotNull);
    expect((await store.listRoutines()).single.id, 'r');
    expect((await store.listWakeRecords()).single.id, 'legacy-w');
    expect((await store.listRuns()).single.id, 'legacy-run');
    expect(await store.loadSession(), isNull);
    await store.commitSession(
      checkpoint(0, wakeId: 'legacy-w', runId: 'legacy-run'),
    );
    expect((await store.loadSession())!.runId, 'legacy-run');
  });
}
