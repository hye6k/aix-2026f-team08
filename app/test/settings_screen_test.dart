import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/app.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/ports.dart';
import 'package:morning_routine/data/sqlite_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

AppSettings example() => AppSettings(
  arrivalTime: ClockTime(9, 0),
  travelDuration: const Duration(minutes: 30),
  sleepDuration: const Duration(hours: 8),
  wakeMode: WakeMode.manual,
  manualWakeTime: ClockTime(7, 0),
  detectionStart: ClockTime(22, 0),
  detectionEnd: ClockTime(2, 0),
);

class TestStore implements RoutineStore {
  AppSettings? value = example();
  bool failLoad = false;
  bool failSave = false;
  int saves = 0;
  Completer<void>? gate;
  @override
  Future<AppSettings?> loadSettings() async {
    if (failLoad) throw StateError('load');
    return value;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    saves++;
    if (gate != null) await gate!.future;
    if (failSave) throw StateError('save');
    value = settings;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> open(WidgetTester tester, RoutineStore store) async {
  await tester.pumpWidget(MorningRoutineApp(store: store));
  await tester.ensureVisible(find.text('시간 설정'));
  await tester.tap(find.text('시간 설정'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('기간 범위 오류를 막고 이동 0과 수면 24시간을 저장한다', (tester) async {
    final store = TestStore();
    await open(tester, store);
    Future<void> edit(int index, String value) async {
      final field = find.byType(TextFormField).at(index);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await edit(0, '25');
    await tap(tester, '설정 저장');
    expect(store.saves, 0);
    await edit(0, '0');
    await edit(1, '0');
    await edit(2, '0');
    await tap(tester, '설정 저장');
    expect(store.saves, 0);
    await edit(2, '24');
    await tap(tester, '설정 저장');
    expect(store.value!.travelDuration, Duration.zero);
    expect(store.value!.sleepDuration, const Duration(hours: 24));
    expect(store.saves, 1);
  });
  testWidgets('모드 전환과 선택기 취소가 수동 입력을 보존한다', (tester) async {
    await open(tester, TestStore());
    expect(find.text('07:00'), findsOneWidget);
    await tap(tester, '권장 시각 사용');
    expect(find.text('07:00'), findsNothing);
    await tap(tester, '직접 지정');
    expect(find.text('07:00'), findsOneWidget);
    await tap(tester, '07:00');
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tap(tester, '취소');
    expect(find.text('07:00'), findsOneWidget);
  });
  testWidgets('신규 필수 입력 누락은 저장하지 않는다', (tester) async {
    final store = TestStore()..value = null;
    await open(tester, store);
    await tap(tester, '설정 저장');
    expect(store.saves, 0);
    expect(find.text('목표 도착 시각을 선택해 주세요.'), findsOneWidget);
  });
  testWidgets('조회 실패 재시도와 저장 실패 후 입력 유지 및 중복 저장 차단', (tester) async {
    final store = TestStore()..failLoad = true;
    await open(tester, store);
    expect(find.text('다시 불러오기'), findsOneWidget);
    store.failLoad = false;
    await tap(tester, '다시 불러오기');
    store.failSave = true;
    await tap(tester, '설정 저장');
    expect(find.text('설정을 저장했어요.'), findsNothing);
    expect(find.widgetWithText(TextFormField, '30'), findsOneWidget);
    store.failSave = false;
    store.gate = Completer<void>();
    await tester.tap(find.text('다시 저장'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(store.saves, 2);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('설정을 저장했어요.'), findsOneWidget);
  });
  testWidgets('실제 SQLite 수정 저장 후 DB와 화면 재생성으로 복원한다', (tester) async {
    await tester.runAsync(() async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp('t04-ui-');
      var store = await SqliteRoutineStore.open(
        '${directory.path}/settings.db',
        factory: databaseFactoryFfi,
      );
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      await store.saveSettings(example());
      await open(tester, store);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(find.byType(TextFormField).at(1), '45');
      await tap(tester, '설정 저장');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('설정을 저장했어요.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await store.close();
      store = await SqliteRoutineStore.open(
        '${directory.path}/settings.db',
        factory: databaseFactoryFfi,
      );
      await open(tester, store);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '45'), findsOneWidget);
      expect(find.text('07:00'), findsOneWidget);
      expect(find.textContaining('22:00~다음 날 02:00'), findsOneWidget);
    });
  });
  testWidgets('작은 화면과 큰 글자에서 저장 버튼 접근 가능', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, TestStore());
    await tap(tester, '설정 저장');
    expect(find.text('설정을 저장했어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
