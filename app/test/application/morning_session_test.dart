import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/application/morning_session.dart';
import 'package:morning_routine/application/session_port.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/ports.dart';
import 'package:morning_routine/domain/alarm_coordinator.dart';

class MemoryStore implements SessionStore {
  AppSettings? settings;
  final routines = <Routine>[];
  final wakes = <WakeRecord>[];
  final runs = <RoutineRun>[];
  SessionCheckpoint? checkpoint;
  bool fail = false;
  int commits = 0;
  @override
  Future<SessionCheckpoint?> loadSession() async => checkpoint;
  @override
  Future<void> commitSession(
    SessionCheckpoint next, {
    AppSettings? settings,
    Routine? routine,
    WakeRecord? wake,
    RoutineRun? run,
  }) async {
    if (fail) throw StateError('disk');
    if (next.revision <= (checkpoint?.revision ?? -1)) {
      throw StateError('stale');
    }
    if (settings != null) this.settings = settings;
    if (routine != null) {
      routines.removeWhere((r) => r.id == routine.id);
      routines.add(routine);
    }
    if (wake != null) {
      wakes.removeWhere((w) => w.id == wake.id);
      wakes.add(wake);
    }
    if (run != null) {
      runs.removeWhere((r) => r.id == run.id);
      runs.add(run);
    }
    checkpoint = next;
    commits++;
  }

  @override
  Future<AppSettings?> loadSettings() async => settings;
  @override
  Future<List<Routine>> listRoutines() async => [...routines];
  @override
  Future<List<WakeRecord>> listWakeRecords() async => [...wakes];
  @override
  Future<List<RoutineRun>> listRuns() async => [...runs];
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DelayedStore extends MemoryStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<AppSettings?> loadSettings() async {
    entered.complete();
    await release.future;
    return super.loadSettings();
  }
}

class Platform implements AlarmPort, ActivitySignalPort {
  final input = StreamController<ActivitySignal>.broadcast();
  final scheduled = <AlarmRequest>[];
  final cancelled = <String>[];
  bool deny = false, failCancel = false, failSchedule = false;
  DateTime? failAt;
  @override
  Stream<ActivitySignal> get signals => input.stream;
  @override
  Future<AlarmPermission> permission() async =>
      deny ? AlarmPermission.denied : AlarmPermission.granted;
  @override
  Future<void> schedule(AlarmRequest request) async {
    if (failSchedule || request.at == failAt) throw StateError('schedule');
    scheduled.add(request);
  }

  @override
  Future<void> cancel(String id) async {
    if (failCancel) throw StateError('cancel');
    cancelled.add(id);
  }
}

AppSettings settings({bool midnight = false}) => AppSettings(
  arrivalTime: ClockTime(midnight ? 1 : 9, 0),
  travelDuration: const Duration(minutes: 30),
  sleepDuration: const Duration(hours: 8),
  wakeMode: WakeMode.recommended,
  detectionStart: ClockTime(midnight ? 23 : 6, 0),
  detectionEnd: ClockTime(midnight ? 1 : 9, 0),
);
Routine routine() => Routine(
  id: 'r',
  name: '아침',
  steps: [
    RoutineStep(id: 'a', name: '씻기', expected: const Duration(minutes: 10)),
    RoutineStep(id: 'b', name: '식사', expected: const Duration(minutes: 10)),
  ],
);
void main() {
  late MemoryStore db;
  late Platform platform;
  late MorningSession session;
  late DateTime now;
  var id = 0;
  MorningSession create() => MorningSession(
    store: db,
    alarmPort: platform,
    signals: platform,
    clock: () => now,
    newId: () => 'id-${id++}',
  );
  Future<void> configured({bool midnight = false}) async {
    await session.initialize();
    await session.configure(
      settings: settings(midnight: midnight),
      routine: routine(),
      arrivalDay: DateTime.utc(2026, 11, 8),
    );
  }

  Future<void> candidate() =>
      session.observe(ActivitySignal(at: now, source: WakeSource.screenOn));
  setUp(() {
    db = MemoryStore();
    platform = Platform();
    now = DateTime.utc(2026, 11, 8, 7);
    session = create();
  });
  tearDown(() async {
    await session.close();
    await platform.input.close();
  });
  test('설정·루틴·회차 저장 뒤 계획 알람을 예약한다', () async {
    await configured();
    expect(session.view.plan!.alarmAt, DateTime.utc(2026, 11, 8, 8, 10));
    expect(db.checkpoint!.routineId, 'r');
    expect(platform.scheduled.single.at, session.view.plan!.alarmAt);
  });
  test('DB 실패는 선택 상태와 OS 예약을 바꾸지 않는다', () async {
    await session.initialize();
    db.fail = true;
    await expectLater(
      session.configure(
        settings: settings(),
        routine: routine(),
        arrivalDay: now,
      ),
      throwsStateError,
    );
    expect(session.view.plan, isNull);
    expect(platform.scheduled, isEmpty);
    db.fail = false;
    await configured();
    expect(session.view.plan, isNotNull);
  });
  test('권한 거부를 성공 상태로 표시하지 않는다', () async {
    platform.deny = true;
    await configured();
    expect(session.view.alarmResult, AlarmApplyResult.permissionDenied);
    expect(platform.scheduled, isEmpty);
  });
  test('동일 시각 반복 후보는 기록 한 건으로 묶는다', () async {
    await configured();
    await Future.wait([candidate(), candidate(), candidate()]);
    expect(db.wakes.length, 1);
    expect(session.view.wake!.status, WakeStatus.pending);
  });
  test('다른 날짜와 종료 경계의 신호는 거부한다', () async {
    await configured();
    await session.observe(
      ActivitySignal(
        at: now.subtract(const Duration(days: 1)),
        source: WakeSource.screenOn,
      ),
    );
    now = DateTime.utc(2026, 11, 8, 9);
    await candidate();
    expect(session.view.wake, isNull);
  });
  test('자정 구간은 이전 밤부터 당일 종료 전까지다', () async {
    await configured(midnight: true);
    now = DateTime.utc(2026, 11, 7, 23, 59);
    await candidate();
    expect(session.view.wake, isNotNull);
  });
  test('후보 취소 뒤 1분 전에는 재감지하지 않는다', () async {
    await configured();
    await candidate();
    await session.cancelCandidate();
    now = now.add(const Duration(seconds: 59));
    await candidate();
    expect(db.wakes.length, 1);
    now = now.add(const Duration(seconds: 1));
    await candidate();
    expect(db.wakes.length, 2);
  });
  test('기상 확정 저장 후 취소 오류가 나도 기록과 재시도 정보가 남는다', () async {
    await configured();
    await candidate();
    platform.failCancel = true;
    await expectLater(session.confirmWake(), throwsStateError);
    expect(session.view.wake!.status, WakeStatus.confirmed);
    expect(db.checkpoint!.cancellationPending, isTrue);
    platform.failCancel = false;
    await session.retryAlarm();
    expect(db.checkpoint!.cancellationPending, isFalse);
  });
  test('기상 확정 DB 실패는 알람을 취소하지 않는다', () async {
    await configured();
    await candidate();
    final before = platform.cancelled.length;
    db.fail = true;
    await expectLater(session.confirmWake(), throwsStateError);
    expect(platform.cancelled.length, before);
    expect(session.view.wake!.status, WakeStatus.pending);
  });
  test('수동 루틴 시작은 기상 확정이 아니며 중복 시작을 묶는다', () async {
    await configured();
    await Future.wait([session.startRoutine(), session.startRoutine()]);
    expect(db.runs.length, 1);
    expect(session.view.wake, isNull);
    expect(session.view.prediction!.isConditional, isTrue);
  });
  test('단계 중복 완료는 다음 단계를 자동 완료하지 않는다', () async {
    await configured();
    await session.startRoutine();
    now = now.add(const Duration(minutes: 2));
    await Future.wait([session.completeStep('a'), session.completeStep('a')]);
    expect(session.view.run!.steps[1].status, StepStatus.active);
    expect(session.view.run!.revision, 1);
    await session.skipStep('b');
    expect(session.view.run!.status, RunStatus.completed);
  });
  test('다시 울림과 알람 해제는 후보 상태를 바꾸지 않는다', () async {
    await configured();
    await candidate();
    await session.snooze();
    expect(platform.scheduled.last.at, now.add(const Duration(minutes: 5)));
    await session.dismissAlarm();
    expect(session.view.wake!.status, WakeStatus.pending);
  });
  test('수동 기상은 사용자 시각을 보존하고 루틴을 자동 시작하지 않는다', () async {
    await configured();
    final at = now.subtract(const Duration(minutes: 20));
    await session.recordManualWake(at);
    expect(session.view.wake!.wakeAt, at);
    expect(session.view.run, isNull);
  });
  test('복원 시 실행 경과를 반영하고 OS 알람을 다시 예약하지 않는다', () async {
    await configured();
    await candidate();
    await session.startRoutine();
    final before = platform.scheduled.length;
    await session.close();
    now = now.add(const Duration(minutes: 30));
    session = create();
    await session.initialize();
    expect(session.view.wake!.status, WakeStatus.pending);
    expect(session.view.run!.status, RunStatus.running);
    expect(
      session.view.prediction!.remainingPreparation,
      const Duration(minutes: 11),
    );
    expect(platform.scheduled.length, before);
  });
  test('종료한 실행은 재실행 후에도 종료 상태다', () async {
    await configured();
    await session.startRoutine();
    await session.stopRoutine();
    await session.close();
    session = create();
    await session.initialize();
    expect(session.view.run!.status, RunStatus.stopped);
    expect(session.view.prediction, isNull);
  });
  test('시계 역행을 오류 상태로 표시하고 실행을 변경하지 않는다', () async {
    await configured();
    await session.startRoutine();
    now = now.subtract(const Duration(minutes: 1));
    expect(session.view.prediction, isNull);
    expect(session.view.error, isArgumentError);
    await expectLater(session.completeStep('a'), throwsArgumentError);
    expect(session.view.run!.revision, 0);
  });
  test('진행 중에는 설정·선택 루틴을 교체하지 않는다', () async {
    await configured();
    await session.startRoutine();
    await expectLater(
      session.configure(
        settings: settings(),
        routine: routine(),
        arrivalDay: now.add(const Duration(days: 1)),
      ),
      throwsStateError,
    );
    expect(session.view.run!.status, RunStatus.running);
  });
  test('같은 날 목표 시각 변경은 확정 기상을 지우거나 알람을 재개하지 않는다', () async {
    await configured();
    await candidate();
    await session.confirmWake();
    final id = session.view.wake!.id;
    final before = platform.scheduled.length;
    final updated = AppSettings(
      arrivalTime: ClockTime(10, 0),
      travelDuration: const Duration(minutes: 30),
      sleepDuration: const Duration(hours: 8),
      wakeMode: WakeMode.recommended,
      detectionStart: ClockTime(6, 0),
      detectionEnd: ClockTime(9, 0),
    );
    await session.configure(
      settings: updated,
      routine: routine(),
      arrivalDay: now,
    );
    expect(session.view.wake?.id, id);
    expect(platform.scheduled.length, before);
  });
  test('같은 날 루틴 교체는 기상을 보존하고 이전 완료 실행만 분리한다', () async {
    await configured();
    await candidate();
    await session.confirmWake();
    await session.startRoutine();
    await session.completeStep('a');
    await session.completeStep('b');
    final wakeId = session.view.wake!.id;
    final other = Routine(
      id: 'other',
      name: '다른 준비',
      steps: [
        RoutineStep(id: 'c', name: '옷입기', expected: const Duration(minutes: 5)),
      ],
    );
    await session.configure(
      settings: settings(),
      routine: other,
      arrivalDay: now,
    );
    expect(session.view.wake?.id, wakeId);
    expect(session.view.run, isNull);
    await session.startRoutine();
    expect(session.view.run!.wakeRecordId, wakeId);
  });
  test('예약 실패는 재실행 후에도 재시도 대상으로 남는다', () async {
    platform.failSchedule = true;
    await expectLater(configured(), throwsStateError);
    expect(db.checkpoint!.alarmUpdatePending, isTrue);
    await session.close();
    session = create();
    await session.initialize();
    expect(session.view.alarmUpdatePending, isTrue);
    expect(session.view.error, isStateError);
    platform.failSchedule = false;
    await session.retryAlarm();
    expect(session.view.alarmUpdatePending, isFalse);
    expect(platform.scheduled.length, 1);
  });
  test('대기 없는 재적용 실패는 대상 시각과 함께 재실행 후에도 남는다', () async {
    await configured();
    final at = session.view.plan!.alarmAt;
    await session.nativeAlarmChanged();
    platform.failSchedule = true;
    await expectLater(session.retryAlarm(), throwsStateError);
    expect(db.checkpoint!.alarmUpdatePending, isTrue);
    expect(db.checkpoint!.alarmPendingAt, at);
    await session.close();
    session = create();
    await session.initialize();
    expect(session.view.alarmUpdatePending, isTrue);
    expect(session.view.alarmPendingAt, at);
    platform.failSchedule = false;
    await session.retryAlarm();
    expect(session.view.alarmUpdatePending, isFalse);
  });
  test('초기화 중 종료해도 신호 구독이 남지 않는다', () async {
    final delayed = DelayedStore();
    final other = MorningSession(
      store: delayed,
      alarmPort: platform,
      signals: platform,
      clock: () => now,
      newId: () => 'id',
    );
    final initializing = other.initialize();
    await delayed.entered.future;
    final closing = other.close();
    final closingAgain = other.close();
    delayed.release.complete();
    await initializing;
    await closing;
    await closingAgain;
    expect(platform.input.hasListener, isFalse);
  });
  test('대기 없는 재적용의 권한 거부와 저장 실패를 구분한다', () async {
    await configured();
    await session.nativeAlarmChanged();
    final count = platform.scheduled.length;
    db.fail = true;
    await expectLater(session.retryAlarm(), throwsStateError);
    expect(platform.scheduled.length, count);
    db.fail = false;
    platform.deny = true;
    await session.retryAlarm();
    expect(db.checkpoint!.alarmUpdatePending, isTrue);
    await session.close();
    session = create();
    await session.initialize();
    expect(session.view.alarmUpdatePending, isTrue);
    platform.deny = false;
    await session.retryAlarm();
    expect(session.view.alarmUpdatePending, isFalse);
  });
  test('권한 거부 뒤 재실행해도 저장된 예약 대기를 유지한다', () async {
    platform.deny = true;
    await configured();
    await session.close();
    session = create();
    await session.initialize();
    expect(session.view.alarmUpdatePending, isTrue);
    platform.deny = false;
    await session.retryAlarm();
    expect(session.view.alarmUpdatePending, isFalse);
  });
  test('다시 울림 실패 후 재시도는 원래 계획 대신 5분 뒤 시각을 적용한다', () async {
    await configured();
    platform.failSchedule = true;
    await expectLater(session.snooze(), throwsStateError);
    final at = now.add(const Duration(minutes: 5));
    expect(db.checkpoint!.alarmPendingAt, at);
    await session.close();
    session = create();
    await session.initialize();
    platform.failSchedule = false;
    await session.retryAlarm();
    expect(platform.scheduled.last.at, at);
  });
  test('해제 실패 후 재시도는 재예약하지 않고 취소한다', () async {
    await configured();
    final count = platform.scheduled.length;
    platform.failCancel = true;
    await expectLater(session.dismissAlarm(), throwsStateError);
    expect(db.checkpoint!.alarmUpdatePending, isTrue);
    expect(db.checkpoint!.alarmPendingAt, isNull);
    await session.close();
    session = create();
    await session.initialize();
    platform.failCancel = false;
    await session.retryAlarm();
    expect(platform.scheduled.length, count);
    expect(session.view.alarmUpdatePending, isFalse);
  });
  test('구간 밖 신호는 기존 pending 후보를 삭제하지 않는다', () async {
    await configured();
    await candidate();
    final old = session.view.wake!;
    final commits = db.commits;
    now = DateTime.utc(2026, 11, 8, 9);
    await candidate();
    expect(session.view.wake, same(old));
    expect(session.view.wake!.status, WakeStatus.pending);
    expect(db.commits, commits);
  });
  test('기상 확정은 다음 날 알람을 만들지 않고 새 날짜 계획에서만 예약한다', () async {
    await configured();
    await candidate();
    await session.confirmWake();
    final count = platform.scheduled.length;
    now = now.add(const Duration(days: 1));
    await session.initialize();
    expect(platform.scheduled.length, count);
    await session.configure(
      settings: settings(),
      routine: routine(),
      arrivalDay: now,
    );
    expect(platform.scheduled.length, count + 1);
    expect(platform.scheduled.last.at, DateTime.utc(2026, 11, 9, 8, 10));
    expect(session.view.wake, isNull);
  });
  test('네이티브 다시 울림 반영은 OS를 건드리지 않고 다음 명시 적용의 캐시만 갱신한다', () async {
    await configured();
    final schedules = platform.scheduled.length,
        cancels = platform.cancelled.length;
    await session.nativeAlarmChanged();
    expect(platform.scheduled.length, schedules);
    expect(platform.cancelled.length, cancels);
    await session.retryAlarm();
    expect(platform.scheduled.length, schedules + 1);
  });
  test('다시 울림 실패 뒤 이전 알람 복구와 새 의도 대기를 함께 유지한다', () async {
    await configured();
    platform.failAt = now.add(const Duration(minutes: 5));
    await expectLater(
      session.snooze(),
      throwsA(
        isA<AlarmApplyFailure>().having(
          (f) => f.previousRestored,
          '이전 복구',
          true,
        ),
      ),
    );
    expect(session.view.alarmUpdatePending, isTrue);
    expect(session.view.alarmPendingAt, platform.failAt);
    expect(platform.scheduled.last.at, DateTime.utc(2026, 11, 8, 8, 10));
  });
  test('누락된 활성 참조는 조용히 초기화하지 않는다', () async {
    await configured();
    await candidate();
    await session.close();
    db.wakes.clear();
    session = create();
    await expectLater(session.initialize(), throwsStateError);
    expect(db.checkpoint!.wakeId, isNotNull);
  });
}
