import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/morning_runtime.dart';
import 'package:morning_routine/application/session_routine_store.dart';
import 'package:morning_routine/data/sqlite_store.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/ports.dart';
import 'package:morning_routine/platform/android_morning_platform.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestNative extends AndroidMorningPlatform {
  TestNative(this.input) : super(events: input.stream);
  final StreamController<Object?> input;
  final scheduled = <AlarmRequest>[];
  bool failSchedule = false;
  @override
  Future<AndroidPermissionState> permissions() async =>
      const AndroidPermissionState(exactAlarm: true, notifications: true);
  @override
  Future<AlarmPermission> permission() async => AlarmPermission.granted;
  @override
  Future<void> schedule(AlarmRequest request) async {
    if (failSchedule) throw StateError('schedule failure');
    scheduled.add(request);
  }

  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> showWakeCandidate(WakeRecord candidate) async {}
  @override
  Future<void> clearWakeCandidate() async {}
  @override
  Future<List<AndroidMorningEvent>> pendingAlarmEvents() async => [];
  @override
  Future<void> acknowledgeAlarmEvent(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final now = DateTime(2026, 11, 11, 7);
  AppSettings settings([int travel = 30]) => AppSettings(
    arrivalTime: ClockTime(9, 0),
    travelDuration: Duration(minutes: travel),
    sleepDuration: const Duration(hours: 8),
    wakeMode: WakeMode.recommended,
    detectionStart: ClockTime(6, 0),
    detectionEnd: ClockTime(8, 0),
  );
  Routine routine([int first = 10]) => Routine(
    id: 'routine',
    name: '등교',
    steps: [
      RoutineStep(
        id: 'wash',
        name: '세면',
        expected: Duration(minutes: first),
      ),
      RoutineStep(
        id: 'meal',
        name: '식사',
        expected: const Duration(minutes: 20),
      ),
    ],
  );
  Future<(MorningRuntime, TestNative, StreamController<Object?>)> open(
    String path,
  ) async {
    final stream = StreamController<Object?>.broadcast();
    final native = TestNative(stream);
    var id = 0;
    final runtime = await MorningRuntime.open(
      openStore: () =>
          SqliteRoutineStore.open(path, factory: databaseFactoryFfi),
      platform: native,
      clock: () => now,
      newId: () => 'r-${id++}',
    );
    return (runtime, native, stream);
  }

  test('공유 편집은 활성 세션을 갱신하고 진행 중 변경과 선택 루틴 삭제를 막는다', () async {
    final dir = await Directory.systemTemp.createTemp('ui-session-');
    final (runtime, native, stream) = await open('${dir.path}/app.db');
    try {
      final editor = SessionRoutineStore(runtime.session);
      await editor.saveSettings(settings());
      await editor.saveRoutine(routine());
      await runtime.session.configure(
        settings: settings(),
        routine: routine(),
        arrivalDay: now,
      );
      expect(native.scheduled.last.at, DateTime(2026, 11, 11, 8));
      await editor.saveSettings(settings(45));
      expect(runtime.session.view.plan!.alarmAt, DateTime(2026, 11, 11, 7, 45));
      expect(
        (await editor.loadSettings())!.travelDuration,
        const Duration(minutes: 45),
      );
      await editor.saveRoutine(routine(20));
      expect(runtime.session.view.plan!.alarmAt, DateTime(2026, 11, 11, 7, 35));
      expect(
        (await editor.listRoutines()).single.steps.first.expected,
        const Duration(minutes: 20),
      );
      await expectLater(
        editor.deleteRoutine('routine'),
        throwsA(isA<StoreActionBlocked>()),
      );
      await runtime.session.startRoutine();
      await expectLater(
        editor.saveSettings(settings(20)),
        throwsA(isA<StoreActionBlocked>()),
      );
      expect(
        (await editor.loadSettings())!.travelDuration,
        const Duration(minutes: 45),
      );
      expect(runtime.session.view.run!.status, RunStatus.running);
    } finally {
      await runtime.close();
      await stream.close();
      await dir.delete(recursive: true);
    }
  });

  test('설정은 저장됐지만 알람 갱신이 실패하면 대기를 보존하고 재시도한다', () async {
    final dir = await Directory.systemTemp.createTemp('ui-session-fail-');
    final (runtime, native, stream) = await open('${dir.path}/app.db');
    try {
      final editor = SessionRoutineStore(runtime.session);
      await editor.saveSettings(settings());
      await editor.saveRoutine(routine());
      await runtime.session.configure(
        settings: settings(),
        routine: routine(),
        arrivalDay: now,
      );
      native.failSchedule = true;
      var warnings = 0;
      final editing = SessionRoutineStore(
        runtime.session,
        onAlarmPending: () => warnings++,
      );
      await editing.saveSettings(settings(45));
      expect(
        (await editor.loadSettings())!.travelDuration,
        const Duration(minutes: 45),
      );
      expect(runtime.session.view.alarmUpdatePending, isTrue);
      expect(warnings, 1);
      native.failSchedule = false;
      await runtime.session.retryAlarm();
      expect(runtime.session.view.alarmUpdatePending, isFalse);
      expect(native.scheduled.last.at, DateTime(2026, 11, 11, 7, 45));
    } finally {
      await runtime.close();
      await stream.close();
      await dir.delete(recursive: true);
    }
  });
}
