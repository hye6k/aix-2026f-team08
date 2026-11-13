import 'dart:async';

import '../domain/models.dart';
import '../domain/ports.dart';
import '../domain/planning.dart';
import '../domain/wake_tracker.dart';
import '../domain/routine_engine.dart';
import '../domain/arrival_prediction.dart';
import '../domain/alarm_coordinator.dart';
import 'session_port.dart';

class SessionView {
  const SessionView({
    required this.routines,
    this.settings,
    this.plan,
    this.wake,
    this.run,
    this.prediction,
    this.error,
    this.alarmResult,
    this.cancellationPending = false,
    this.alarmUpdatePending = false,
    this.alarmPendingAt,
  });
  final List<Routine> routines;
  final AppSettings? settings;
  final DailyPlan? plan;
  final WakeRecord? wake;
  final RoutineRun? run;
  final ArrivalPrediction? prediction;
  final Object? error;
  final AlarmApplyResult? alarmResult;
  final bool cancellationPending;
  final bool alarmUpdatePending;
  final DateTime? alarmPendingAt;
}

/// UI·DB·Android 구체 구현과 분리된, 저장 후 상태를 공개하는 조작 창구.
class MorningSession {
  MorningSession({
    required this.store,
    required this.alarmPort,
    required this.signals,
    required this.clock,
    required this.newId,
  }) : _alarms = AlarmCoordinator(alarmPort, clock: clock);
  final SessionStore store;
  final AlarmPort alarmPort;
  final ActivitySignalPort signals;
  final DateTime Function() clock;
  final String Function() newId;
  static const alarmId = 'morning-wake';
  final _wakeTracker = WakeTracker();
  final _engine = const RoutineEngine();
  final AlarmCoordinator _alarms;
  final _changes = StreamController<SessionView>.broadcast();
  Stream<SessionView> get changes => _changes.stream;
  StreamSubscription<ActivitySignal>? _subscription;
  Future<void> _tail = Future<void>.value();
  bool _initialized = false;
  bool _closed = false;
  List<Routine> _routines = [];
  AppSettings? _settings;
  Routine? _routine;
  DailyPlan? _plan;
  SessionCheckpoint? _checkpoint;
  WakeRecord? _wake;
  RoutineRun? _run;
  Object? _error;
  AlarmApplyResult? _alarmResult;

  SessionView get view {
    ArrivalPrediction? prediction;
    Object? error = _error;
    if (error == null && (_checkpoint?.alarmUpdatePending ?? false)) {
      error = StateError('저장된 알람 변경을 적용하지 못했습니다. 재시도해 주세요.');
    }
    if (_plan != null &&
        _routine != null &&
        _run?.status != RunStatus.stopped) {
      try {
        prediction = ArrivalPredictor().calculate(
          now: clock(),
          targetArrival: _plan!.arrivalAt,
          travel: _settings!.travelDuration,
          routine: _routine!,
          wakeConfirmed: _wake?.status == WakeStatus.confirmed,
          run: _run,
        );
      } catch (e) {
        error = e;
      }
    }
    return SessionView(
      routines: List.unmodifiable(_routines),
      settings: _settings,
      plan: _plan,
      wake: _wake,
      run: _run,
      prediction: prediction,
      error: error,
      alarmResult: _alarmResult,
      cancellationPending: _checkpoint?.cancellationPending ?? false,
      alarmUpdatePending: _checkpoint?.alarmUpdatePending ?? false,
      alarmPendingAt: _checkpoint?.alarmPendingAt,
    );
  }

  void refreshClock() {
    if (!_closed) _changes.add(view);
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    if (_closed) return Future<T>.error(StateError('세션이 종료되었습니다.'));
    final result = _tail.then((_) async {
      _error = null;
      try {
        final value = await action();
        refreshClock();
        return value;
      } catch (e) {
        _error = e;
        refreshClock();
        rethrow;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  void _ready() {
    if (!_initialized) throw StateError('먼저 initialize를 호출하세요.');
  }

  Future<void> initialize() => _serial(() async {
    if (_initialized) return;
    final settings = await store.loadSettings();
    final routines = await store.listRoutines();
    final checkpoint = await store.loadSession();
    Routine? routine;
    WakeRecord? wake;
    RoutineRun? run;
    DailyPlan? plan;
    if (checkpoint != null) {
      if (settings == null) throw StateError('복원할 설정이 없습니다.');
      routine = routines.where((r) => r.id == checkpoint.routineId).single;
      plan = calculateDailyPlan(
        arrivalDay: checkpoint.arrivalDay,
        settings: settings,
        routine: routine,
      );
      if (checkpoint.wakeId != null) {
        wake = (await store.listWakeRecords())
            .where((w) => w.id == checkpoint.wakeId)
            .single;
      }
      if (checkpoint.runId != null) {
        run = (await store.listRuns())
            .where((r) => r.id == checkpoint.runId)
            .single;
      }
      if (run != null && run.routineId != routine.id) {
        throw StateError('실행과 선택 루틴이 다릅니다.');
      }
      if (checkpoint.cancellationPending &&
          wake?.status != WakeStatus.confirmed) {
        throw StateError('취소 대기 기록이 확정 기상이 아닙니다.');
      }
    }
    _settings = settings;
    _routines = routines;
    _checkpoint = checkpoint;
    _routine = routine;
    _plan = plan;
    _wake = wake;
    _run = run;
    _initialized = true;
    _subscription = signals.signals.listen(
      (signal) {
        observe(signal).catchError((Object e) {});
      },
      onError: (Object e) {
        _error = e;
        refreshClock();
      },
    );
    // 이미 해제·다시 울림한 OS 예약을 앱 재실행만으로 덮어쓰지 않는다.
    if (checkpoint?.cancellationPending ?? false) await _finishCancellation();
  });
  Future<void> configure({
    required AppSettings settings,
    required Routine routine,
    required DateTime arrivalDay,
  }) => _serial(() async {
    _ready();
    final plan = calculateDailyPlan(
      arrivalDay: arrivalDay,
      settings: settings,
      routine: routine,
    );
    final oldDay = _checkpoint?.arrivalDay;
    final sameDay =
        oldDay != null &&
        oldDay.year == arrivalDay.year &&
        oldDay.month == arrivalDay.month &&
        oldDay.day == arrivalDay.day;
    final sameRoutine = _checkpoint?.routineId == routine.id;
    if (_run?.status == RunStatus.running) {
      throw StateError('진행 중인 루틴을 먼저 완료하거나 종료하세요.');
    }
    if (_checkpoint?.cancellationPending ?? false) await _finishCancellation();
    final checkpoint = SessionCheckpoint(
      revision: (_checkpoint?.revision ?? -1) + 1,
      routineId: routine.id,
      arrivalDay: arrivalDay,
      wakeId: sameDay ? _wake?.id : null,
      runId: sameDay && sameRoutine ? _run?.id : null,
      alarmUpdatePending: true,
      alarmPendingAt: sameDay && _wake?.status == WakeStatus.confirmed
          ? null
          : plan.alarmAt,
    );
    await store.commitSession(checkpoint, settings: settings, routine: routine);
    _settings = settings;
    _routine = routine;
    _plan = plan;
    _checkpoint = checkpoint;
    _routines = [..._routines.where((r) => r.id != routine.id), routine];
    if (!sameDay) _wake = null;
    if (!sameDay || !sameRoutine) _run = null;
    await _applyAlarm();
  });
  Future<void> retryAlarm() => _serial(() async {
    _ready();
    if (_checkpoint?.cancellationPending ?? false) {
      await _finishCancellation();
    } else {
      await _applyAlarm();
    }
  });
  Future<void> _applyAlarm() async {
    if (_plan == null) throw StateError('저장된 계획이 없습니다.');
    _alarmResult = null;
    final at = (_checkpoint?.alarmUpdatePending ?? false)
        ? _checkpoint!.alarmPendingAt
        : _plan!.alarmAt;
    if (_wake?.status == WakeStatus.confirmed ||
        at == null ||
        !at.isAfter(clock())) {
      await _alarms.cancel(alarmId);
      if (_checkpoint!.alarmUpdatePending) {
        await _persist(alarmUpdatePending: false);
      }
      return;
    }
    _alarmResult = await _alarms.apply(
      AlarmRequest(id: alarmId, at: at),
      now: clock(),
    );
    if (_alarmResult != AlarmApplyResult.permissionDenied &&
        _checkpoint!.alarmUpdatePending) {
      await _persist(alarmUpdatePending: false);
    }
  }

  SessionCheckpoint _next({
    WakeRecord? wake,
    RoutineRun? run,
    bool? cancellationPending,
    bool? alarmUpdatePending,
    DateTime? alarmPendingAt,
  }) {
    final old = _checkpoint ?? (throw StateError('계획을 먼저 저장하세요.'));
    return SessionCheckpoint(
      revision: old.revision + 1,
      routineId: old.routineId,
      arrivalDay: old.arrivalDay,
      wakeId: wake?.id ?? old.wakeId,
      runId: run?.id ?? old.runId,
      cancellationPending: cancellationPending ?? old.cancellationPending,
      alarmUpdatePending: alarmUpdatePending ?? old.alarmUpdatePending,
      alarmPendingAt: alarmUpdatePending == false
          ? null
          : (alarmUpdatePending == true ? alarmPendingAt : old.alarmPendingAt),
    );
  }

  Future<void> _persist({
    WakeRecord? wake,
    RoutineRun? run,
    bool? cancellationPending,
    bool? alarmUpdatePending,
    DateTime? alarmPendingAt,
  }) async {
    final next = _next(
      wake: wake,
      run: run,
      cancellationPending: cancellationPending,
      alarmUpdatePending: alarmUpdatePending,
      alarmPendingAt: alarmPendingAt,
    );
    await store.commitSession(next, wake: wake, run: run);
    _checkpoint = next;
    if (wake != null) _wake = wake;
    if (run != null) _run = run;
  }

  bool _inWindow(DateTime at) {
    if (_plan == null) return false;
    var start = _settings!.detectionStart.on(_plan!.alarmAt);
    var end = _settings!.detectionEnd.on(_plan!.alarmAt);
    if (!end.isAfter(start)) {
      if (_plan!.alarmAt.isBefore(start)) {
        start = start.subtract(const Duration(days: 1));
      } else {
        end = end.add(const Duration(days: 1));
      }
    }
    return !at.isBefore(start) && at.isBefore(end);
  }

  Future<void> observe(ActivitySignal signal) => _serial(() async {
    _ready();
    if (!_inWindow(signal.at) || signal.at.isAfter(clock())) return;
    final next = _wakeTracker.detect(
      id: newId(),
      at: signal.at,
      settings: _settings!,
      source: signal.source,
      previous: _wake,
    );
    if (next != null && !identical(next, _wake)) await _persist(wake: next);
  });
  Future<void> confirmWake() => _serial(() async {
    _ready();
    if (_wake == null) throw StateError('확인할 후보가 없습니다.');
    final next = _wakeTracker.confirm(_wake!, at: clock());
    if (!identical(next, _wake)) {
      await _persist(
        wake: next,
        cancellationPending: true,
        alarmUpdatePending: false,
      );
    }
    if (_checkpoint!.cancellationPending) await _finishCancellation();
  });
  Future<void> recordManualWake(DateTime at) => _serial(() async {
    _ready();
    if (_wake?.status == WakeStatus.confirmed) {
      throw StateError('이미 확정한 기상이 있습니다.');
    }
    final next = _wakeTracker.recordManual(
      id: newId(),
      wakeAt: at,
      recordedAt: clock(),
    );
    await _persist(
      wake: next,
      cancellationPending: true,
      alarmUpdatePending: false,
    );
    await _finishCancellation();
  });
  Future<void> _finishCancellation() async {
    await _alarms.wakeConfirmed(alarmId);
    _alarmResult = null;
    await _persist(cancellationPending: false, alarmUpdatePending: false);
  }

  Future<void> cancelCandidate() => _serial(() async {
    _ready();
    if (_wake == null) throw StateError('취소할 후보가 없습니다.');
    final next = _wakeTracker.cancel(_wake!, at: clock());
    if (!identical(next, _wake)) await _persist(wake: next);
  });
  Future<void> startRoutine() => _serial(() async {
    _ready();
    if (_routine == null) throw StateError('루틴을 먼저 선택하세요.');
    if (_run?.status == RunStatus.running) return;
    final run = _engine.start(
      id: newId(),
      routine: _routine!,
      at: clock(),
      existing: _run,
      confirmedWakeRecordId: _wake?.status == WakeStatus.confirmed
          ? _wake!.id
          : null,
    );
    await _persist(run: run);
  });
  Future<void> completeStep(String id) =>
      _transition((r) => _engine.complete(r, stepId: id, at: clock()));
  Future<void> skipStep(String id) =>
      _transition((r) => _engine.skip(r, stepId: id, at: clock()));
  Future<void> stopRoutine() =>
      _transition((r) => _engine.stop(r, at: clock()));
  Future<void> _transition(RoutineRun Function(RoutineRun) action) =>
      _serial(() async {
        _ready();
        if (_run == null) throw StateError('실행 중인 루틴이 없습니다.');
        final next = action(_run!);
        if (!identical(next, _run)) await _persist(run: next);
      });
  Future<void> snooze() => _serial(() async {
    _ready();
    if (_checkpoint == null || _wake?.status == WakeStatus.confirmed) {
      throw StateError('다시 울릴 기상 계획이 없습니다.');
    }
    final at = clock().add(const Duration(minutes: 5));
    await _persist(alarmUpdatePending: true, alarmPendingAt: at);
    await _applyAlarm();
  });
  Future<void> dismissAlarm() => _serial(() async {
    _ready();
    if (_checkpoint != null) {
      await _persist(alarmUpdatePending: true);
      await _applyAlarm();
    } else {
      await _alarms.cancel(alarmId);
      _alarmResult = null;
    }
  });
  Future<void> nativeAlarmChanged() => _serial(() async {
    _ready();
    await _alarms.invalidate();
    _alarmResult = null;
  });
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _tail;
    await _changes.close();
  }
}
