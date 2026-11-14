import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/app.dart';
import 'package:morning_routine/app/morning_runtime.dart';
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

  testWidgets('실제 SQLite 계획→후보→루틴 진행과 프로세스 재기동 복원', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('ui-session-screen-'),
    ))!;
    final file = '${dir.path}/app.db';
    late MorningRuntime runtime;
    late StreamController<Object?> stream;
    Future<void> launch({bool seed = false}) async {
      await tester.runAsync(() async {
        if (seed) {
          final db = await SqliteRoutineStore.open(
            file,
            factory: databaseFactoryFfi,
          );
          await db.saveSettings(settings());
          await db.saveRoutine(routine());
          await db.close();
        }
        final result = await open(file);
        runtime = result.$1;
        stream = result.$3;
      });
      WidgetsBinding.instance.removeObserver(runtime);
      runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pumpWidget(MorningRoutineApp(runtime: runtime));
      await tester.pump();
    }

    Future<void> until(Finder finder) async {
      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        if (finder.evaluate().isNotEmpty) return;
      }
      fail('화면을 찾지 못함: $finder');
    }

    Future<void> press(String label) async {
      final finder = find.text(label);
      await until(finder);
      await tester.ensureVisible(finder);
      final button = find.ancestor(
        of: finder,
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );
      for (var i = 0; i < 600; i++) {
        if (button.evaluate().isNotEmpty &&
            tester.widget<ButtonStyleButton>(button.first).onPressed != null) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        tester.widget<ButtonStyleButton>(button.first).onPressed,
        isNotNull,
      );
      await tester.runAsync(() async {
        await tester.tap(finder);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> untilState(bool Function() predicate) async {
      for (var i = 0; i < 300; i++) {
        if (predicate()) return;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      fail('세션 저장 상태가 갱신되지 않았습니다.');
    }

    try {
      await launch(seed: true);

      await until(find.text('계획 계산 및 저장'));

      await press('계획 계산 및 저장');
      expect(runtime.session.view.plan, isNotNull);
      await untilState(() {
        final button = find.widgetWithText(FilledButton, '시간 설정');
        return button.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(button).onPressed != null;
      });
      await press('시간 설정');
      await untilState(() => find.byType(TextFormField).evaluate().length >= 2);
      final travelMinutes = find.byType(TextFormField).at(1);
      await tester.ensureVisible(travelMinutes);
      await tester.enterText(travelMinutes, '45');
      await press('설정 저장');
      await until(find.text('설정을 저장했어요.'));
      await tester.pump();
      expect(runtime.session.view.plan!.alarmAt, DateTime(2026, 11, 11, 7, 45));
      await tester.tap(find.byTooltip('뒤로'));
      await tester.pump();
      await until(find.text('계획 계산 및 저장'));
      expect(
        (await tester.runAsync(() => runtime.store.loadSettings()))!
            .travelDuration,
        const Duration(minutes: 45),
      );
      await tester.tap(find.text('진행').last);
      await tester.pump();
      await until(find.text('테스트 기상 신호'));
      await press('테스트 기상 신호');
      await untilState(() => runtime.session.view.wake != null);
      expect(runtime.session.view.wake!.source, WakeSource.test);
      await press('일어났어요');
      await untilState(
        () => runtime.session.view.wake?.status == WakeStatus.confirmed,
      );
      expect(runtime.session.view.wake!.status, WakeStatus.confirmed);
      await press('루틴 시작');
      await until(find.textContaining('경과 시간'));
      await press('현재 단계 완료');
      await untilState(
        () => runtime.session.view.run?.activeStep?.step.id == 'meal',
      );
      expect(runtime.session.view.run!.activeStep!.step.id, 'meal');
      await tester.pumpWidget(const SizedBox());

      await tester.runAsync(() async {
        await runtime.close();
        await stream.close();
      });
      await launch();

      await until(find.text('계획 계산 및 저장'));

      expect(runtime.session.view.wake!.status, WakeStatus.confirmed);
      expect(runtime.session.view.run!.activeStep!.step.id, 'meal');
      await tester.tap(find.text('진행').last);
      await tester.pump();
      await until(find.text('현재 단계 건너뛰기'));
      await press('현재 단계 건너뛰기');
      await untilState(
        () => runtime.session.view.run?.status == RunStatus.completed,
      );
      expect(runtime.session.view.run!.status, RunStatus.completed);
      await until(find.text('지금 출발하면'));
      await tester.tap(find.text('기록').last);
      await tester.pump();
      await until(find.text('등교 · 완료'));
      expect(find.textContaining('기상 확인 완료'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());

      await tester.runAsync(() async {
        await runtime.close();
        await stream.close();
        await dir.delete(recursive: true);
      });
    }
  });
}
