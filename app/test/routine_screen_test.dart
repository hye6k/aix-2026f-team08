import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/app.dart';
import 'package:morning_routine/data/sqlite_store.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/ports.dart';
import 'package:morning_routine/presentation/routine_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Routine sample() => Routine(
  id: 'routine-old',
  name: '등교',
  steps: [
    RoutineStep(id: 'wash', name: '세면', expected: const Duration(minutes: 20)),
    RoutineStep(id: 'meal', name: '식사', expected: const Duration(minutes: 15)),
  ],
);

class RoutineTestStore implements RoutineStore {
  final Map<String, Routine> routines = {};
  bool failLoad = false;
  bool failSave = false;
  bool failDelete = false;
  int saves = 0;
  int deletes = 0;
  Completer<void>? saveGate;
  Completer<void>? deleteGate;
  @override
  Future<List<Routine>> listRoutines() async {
    if (failLoad) throw StateError('load');
    return routines.values.toList();
  }

  @override
  Future<void> saveRoutine(Routine routine) async {
    saves++;
    if (saveGate != null) await saveGate!.future;
    if (failSave) throw StateError('save');
    routines[routine.id] = routine;
  }

  @override
  Future<void> deleteRoutine(String id) async {
    deletes++;
    if (deleteGate != null) await deleteGate!.future;
    if (failDelete) throw StateError('delete');
    routines.remove(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> openLibrary(WidgetTester tester, RoutineStore store) async {
  await tester.pumpWidget(MorningRoutineApp(store: store));
  await tester.tap(find.text('루틴'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('루틴 관리'));
  await tester.tap(find.text('루틴 관리'));
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String value) async {
  final target = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pump();
}

Future<void> icon(WidgetTester tester, String tooltip) async {
  final target = find.byTooltip(tooltip);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('신규 등록·동명 단계·순서 변경과 안정적인 ID', (tester) async {
    final store = RoutineTestStore();
    await openLibrary(tester, store);
    expect(find.textContaining('아직 등록한 루틴'), findsOneWidget);
    await press(tester, '루틴 등록');
    await enter(tester, '루틴명', '아침');
    await enter(tester, '1단계 이름', '준비');
    await enter(tester, '1단계 예상 시간', '10');
    await press(tester, '단계 추가');
    await enter(tester, '2단계 이름', '준비');
    await enter(tester, '2단계 예상 시간', '20');
    await icon(tester, '2단계 위로');
    expect(find.widgetWithText(TextFormField, '20'), findsOneWidget);
    expect(find.text('총 예상 시간: 30분'), findsOneWidget);
    await press(tester, '루틴 저장');
    expect(store.saves, 1);
    final saved = store.routines.values.single;
    expect(saved.steps.map((s) => s.expected.inMinutes), [20, 10]);
    expect(saved.steps.map((s) => s.id).toSet().length, 2);
    expect(saved.steps.map((s) => s.name), ['준비', '준비']);
    await press(tester, '아침');
    await icon(tester, '1단계 아래로');
    await enter(tester, '루틴명', '수정한 아침');
    await press(tester, '루틴 저장');
    final updated = store.routines.values.single;
    expect(updated.id, saved.id);
    expect(
      updated.steps.map((s) => s.id),
      saved.steps.reversed.map((s) => s.id),
    );
  });

  testWidgets('편집 이탈 확인 취소와 폐기는 원본을 보존한다', (tester) async {
    final store = RoutineTestStore()..routines['routine-old'] = sample();
    await openLibrary(tester, store);
    await press(tester, '등교');
    await enter(tester, '루틴명', '저장 안 함');
    await icon(tester, '편집 취소');
    await press(tester, '계속 수정');
    expect(find.widgetWithText(TextFormField, '저장 안 함'), findsOneWidget);
    await icon(tester, '편집 취소');
    await press(tester, '저장하지 않고 나가기');
    expect(store.routines.values.single.name, '등교');
    expect(store.saves, 0);
    expect(find.byType(RoutineEditorScreen), findsNothing);
  });

  testWidgets('조회·저장 오류 재시도와 중복 저장 차단', (tester) async {
    final store = RoutineTestStore()..failLoad = true;
    store.routines['routine-old'] = sample();
    await openLibrary(tester, store);
    expect(find.text('루틴을 불러오지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    store.failLoad = false;
    await press(tester, '다시 불러오기');
    await press(tester, '등교');
    store.failSave = true;
    await press(tester, '루틴 저장');
    expect(find.text('루틴을 저장했어요.'), findsNothing);
    expect(find.widgetWithText(TextFormField, '세면'), findsOneWidget);
    store.failSave = false;
    store.saveGate = Completer<void>();
    await tester.ensureVisible(find.text('다시 저장'));
    await tester.tap(find.text('다시 저장'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(store.saves, 2);
    store.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(RoutineEditorScreen), findsNothing);
  });

  testWidgets('삭제 취소·실패·재시도와 중복 삭제 차단', (tester) async {
    final store = RoutineTestStore()..routines['routine-old'] = sample();
    await openLibrary(tester, store);
    await icon(tester, '등교 삭제');
    await press(tester, '취소');
    expect(store.deletes, 0);
    store.failDelete = true;
    await icon(tester, '등교 삭제');
    await press(tester, '삭제');
    expect(store.routines.length, 1);
    expect(find.text('루틴을 삭제했어요.'), findsNothing);
    store.failDelete = false;
    store.deleteGate = Completer<void>();
    await icon(tester, '등교 삭제');
    await tester.tap(find.text('삭제'));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '등교 삭제',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(store.deletes, 2);
    store.deleteGate!.complete();
    await tester.pumpAndSettle();
    expect(store.routines, isEmpty);
    expect(find.textContaining('아직 등록한 루틴'), findsOneWidget);
  });

  for (final value in ['', '0', '-1', 'abc', '1.5', '1441']) {
    testWidgets('단계 예상 시간 "$value" 저장 거부', (tester) async {
      final store = RoutineTestStore()..routines['routine-old'] = sample();
      await openLibrary(tester, store);
      await press(tester, '등교');
      await enter(tester, '1단계 예상 시간', value);
      await press(tester, '루틴 저장');
      expect(store.saves, 0);
      expect(find.byType(RoutineEditorScreen), findsOneWidget);
    });
  }

  testWidgets('단계 추가·삭제 후 기존 ID를 유지하고 삭제한 ID를 재사용하지 않는다', (tester) async {
    final store = RoutineTestStore()..routines['routine-old'] = sample();
    await openLibrary(tester, store);
    await press(tester, '등교');
    await icon(tester, '2단계 삭제');
    await press(tester, '단계 추가');
    await enter(tester, '2단계 이름', '식사');
    await enter(tester, '2단계 예상 시간', '10');
    await press(tester, '루틴 저장');
    final saved = store.routines['routine-old']!;
    expect(saved.steps.first.id, 'wash');
    expect(saved.steps.last.id, isNot(anyOf('meal', 'wash')));
    expect(saved.steps.map((s) => s.name), ['세면', '식사']);
    expect(saved.expected, const Duration(minutes: 30));
  });

  testWidgets('공백 이름·전체 시간 상한·빈 단계 검증 및 정확히 24시간 허용', (tester) async {
    final store = RoutineTestStore()..routines['routine-old'] = sample();
    await openLibrary(tester, store);
    await press(tester, '등교');
    await enter(tester, '루틴명', '  ');
    await enter(tester, '1단계 이름', '  ');
    await press(tester, '루틴 저장');
    expect(store.saves, 0);
    expect(find.text('루틴명을 입력해 주세요.'), findsOneWidget);
    expect(find.text('단계 이름을 입력해 주세요.'), findsOneWidget);
    await enter(tester, '루틴명', '등교');
    await enter(tester, '1단계 이름', '세면');
    await enter(tester, '1단계 예상 시간', '1440');
    await press(tester, '루틴 저장');
    expect(store.saves, 0);
    expect(find.text('루틴 전체 예상 시간은 24시간을 넘을 수 없어요.'), findsOneWidget);
    await icon(tester, '2단계 삭제');
    await press(tester, '루틴 저장');
    expect(store.routines.values.single.expected, const Duration(hours: 24));
    await press(tester, '등교');
    await icon(tester, '1단계 삭제');
    await press(tester, '루틴 저장');
    expect(store.saves, 1);
    expect(find.text('단계를 한 개 이상 추가해 주세요.'), findsOneWidget);
  });

  testWidgets('분 미만 기존 시간은 이름만 수정할 때 보존한다', (tester) async {
    final store = RoutineTestStore();
    store.routines['r'] = Routine(
      id: 'r',
      name: '짧은 준비',
      steps: [
        RoutineStep(
          id: 's',
          name: '단계',
          expected: const Duration(seconds: 30, microseconds: 123),
        ),
      ],
    );
    await openLibrary(tester, store);
    await press(tester, '짧은 준비');
    await enter(tester, '루틴명', '수정');
    await press(tester, '루틴 저장');
    expect(
      store.routines['r']!.expected,
      const Duration(seconds: 30, microseconds: 123),
    );
  });

  testWidgets('작은 화면·큰 글자·키보드에서 단계 조작과 저장', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = RoutineTestStore()..routines['routine-old'] = sample();
    await openLibrary(tester, store);
    await press(tester, '등교');
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await enter(tester, '1단계 이름', '세면 수정');
    await icon(tester, '1단계 아래로');
    await press(tester, '루틴 저장');
    expect(store.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('실제 SQLite에서 등록·수정·순서·삭제 재조회 및 과거 실행 보존', (tester) async {
    await tester.runAsync(() async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('t05-ui-');
      var store = await SqliteRoutineStore.open(
        '${dir.path}/routines.db',
        factory: databaseFactoryFfi,
      );
      addTearDown(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
      Future<void> settleIo(Finder ready) async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
          if (find
                  .byType(RoutineEditorScreen, skipOffstage: false)
                  .evaluate()
                  .isEmpty &&
              ready.evaluate().isNotEmpty) {
            await tester.pumpAndSettle();
            return;
          }
        }
        expect(
          find.byType(RoutineEditorScreen, skipOffstage: false),
          findsNothing,
        );
        expect(ready, findsWidgets);
      }

      await openLibrary(tester, store);
      await settleIo(find.text('루틴 등록'));
      await press(tester, '루틴 등록');
      await enter(tester, '루틴명', '실제 루틴');
      await enter(tester, '1단계 이름', '세면');
      await enter(tester, '1단계 예상 시간', '20');
      await press(tester, '단계 추가');
      await enter(tester, '2단계 이름', '식사');
      await enter(tester, '2단계 예상 시간', '15');
      await press(tester, '루틴 저장');
      await settleIo(find.text('실제 루틴'));
      final original = (await store.listRoutines()).single;
      final at = DateTime.utc(2026, 11, 10, 7);
      final run = RoutineRun(
        id: 'past-run',
        routineId: original.id,
        routineName: original.name,
        startedAt: at,
        updatedAt: at,
        endedAt: at,
        status: RunStatus.completed,
        steps: [
          for (final step in original.steps)
            StepExecution(
              step: step,
              status: StepStatus.completed,
              startedAt: at,
              endedAt: at,
            ),
        ],
      );
      await store.saveRun(run);
      await press(tester, '실제 루틴');
      await icon(tester, '2단계 위로');
      await enter(tester, '루틴명', '실제 수정');
      await enter(tester, '1단계 이름', '식사 수정');
      await press(tester, '루틴 저장');
      await settleIo(find.text('실제 수정'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await store.close();
      store = await SqliteRoutineStore.open(
        '${dir.path}/routines.db',
        factory: databaseFactoryFfi,
      );
      final updated = (await store.listRoutines()).single;
      expect(updated.id, original.id);
      expect(
        updated.steps.map((s) => s.id),
        original.steps.reversed.map((s) => s.id),
      );
      expect(updated.steps.first.name, '식사 수정');
      expect(updated.steps.first.expected, const Duration(minutes: 15));
      await openLibrary(tester, store);
      await settleIo(find.text('실제 수정'));
      await icon(tester, '실제 수정 삭제');
      await press(tester, '삭제');
      await settleIo(find.textContaining('아직 등록한 루틴'));
      expect(await store.listRoutines(), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await store.close();
      store = await SqliteRoutineStore.open(
        '${dir.path}/routines.db',
        factory: databaseFactoryFfi,
      );
      expect(await store.listRoutines(), isEmpty);
      final preserved = (await store.listRuns()).single;
      expect(preserved.routineName, original.name);
      expect(preserved.steps.map((s) => s.step.name), ['세면', '식사']);
    });
  });
}
