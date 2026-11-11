import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/app.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/presentation/settings_screen.dart';
import 'package:morning_routine/presentation/routine_screen.dart';

import 'support/ui_audit_support.dart';
import 'settings_screen_test.dart' as settings;
import 'routine_screen_test.dart' as routines;

void main() {
  testWidgets('T05 저장 완료 뒤 응답 실패가 있어도 재시도로 새 ID를 중복 생성하지 않는다', (tester) async {
    final store = CommitThenFailStore();
    await routines.openLibrary(tester, store);
    await auditTap(tester, '루틴 등록');
    await auditEnter(tester, '루틴명', '중복 방지');
    await auditEnter(tester, '1단계 이름', '준비');
    await auditEnter(tester, '1단계 예상 시간', '1');
    await auditTap(tester, '루틴 저장');
    final first = store.library.routines.values.single;
    expect(find.byType(RoutineEditorScreen), findsOneWidget);
    await auditTap(tester, '다시 저장');
    expect(store.library.routines.length, 1);
    expect(store.library.routines.values.single.id, first.id);
    expect(
      store.library.routines.values.single.steps.single.id,
      first.steps.single.id,
    );
  });
  testWidgets('T04 입력을 원래대로 되돌리면 미저장 확인 없이 나간다', (tester) async {
    await settings.open(tester, AuditStore());
    await auditEnter(tester, '이동 시간, 분', '45');
    await auditEnter(tester, '이동 시간, 분', '30');
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });
  for (final routinePage in [false, true]) {
    final page = routinePage ? 'T05' : 'T04';
    testWidgets('$page 진입 버튼의 연속 호출은 화면을 하나만 연다', (tester) async {
      final store = AuditStore();
      await tester.pumpWidget(MorningRoutineApp(store: store));
      if (routinePage) {
        await tester.tap(find.text('루틴'));
        await tester.pumpAndSettle();
      }
      final VoidCallback callback;
      if (routinePage) {
        callback = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '루틴 관리'))
            .onPressed!;
      } else {
        callback = tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '시간 설정'),
            )
            .onPressed!;
      }
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(routinePage ? store.routinesReads : store.settingsReads, 1);
      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(RoutineLibraryScreen), findsNothing);
    });
    for (final fail in [false, true]) {
      testWidgets(
        '$page 저장 중 강제 화면 폐기 후 늦은 ${fail ? '실패' : '성공'}는 오류를 만들지 않는다',
        (tester) async {
          final store = AuditStore();
          final gate = Completer<void>();
          if (routinePage) {
            store.library.routines['routine-old'] = routines.sample();
            store.library.saveGate = gate;
            store.library.failSave = fail;
            await routines.openLibrary(tester, store);
            await auditTap(tester, '등교');
          } else {
            store.gate = gate;
            store.failSave = fail;
            await settings.open(tester, store);
          }
          final save = find.text(routinePage ? '루틴 저장' : '설정 저장');
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          gate.complete();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(store.closes, 0);
        },
      );
    }
    testWidgets('$page 어두운 테마에서 입력과 저장 및 터치 대상 크기', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final store = AuditStore();
      store.library.routines['routine-old'] = routines.sample();
      if (routinePage) {
        await routines.openLibrary(tester, store);
        await auditTap(tester, '등교');
      } else {
        await settings.open(tester, store);
      }
      final semantics = tester.ensureSemantics();
      try {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      } finally {
        semantics.dispose();
      }
      await auditTap(tester, routinePage ? '루틴 저장' : '설정 저장');
      expect(tester.takeException(), isNull);
    });
  }
  for (final label in ['이동 시간, 시간', '이동 시간, 분', '수면 시간, 시간', '수면 시간, 분']) {
    for (final input in [
      '',
      ' ',
      '-1',
      '1.5',
      'abc',
      '1e3',
      '+1',
      '１',
      '99999999999999999999999999999999999',
    ]) {
      testWidgets('T04 $label 입력 "$input"은 저장하지 않고 원본 유지', (tester) async {
        final store = AuditStore();
        final original = store.value;
        await settings.open(tester, store);
        await auditEnter(tester, label, input);
        await auditTap(tester, '설정 저장');
        expect(store.saves, 0);
        expect(store.value, same(original));
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final values in [
    ('0', '0', '0', '1', true),
    ('24', '0', '24', '0', true),
    ('23', '59', '23', '59', true),
    ('24', '1', '8', '0', false),
    ('0', '60', '8', '0', false),
    ('0', '0', '0', '0', false),
    ('0', '0', '24', '1', false),
    ('0', '0', '0', '60', false),
    (' 01 ', ' 02 ', '08', '00', true),
  ]) {
    testWidgets(
      'T04 이동 ${values.$1}:${values.$2} 수면 ${values.$3}:${values.$4} 경계',
      (tester) async {
        final store = AuditStore();
        await settings.open(tester, store);
        await auditEnter(tester, '이동 시간, 시간', values.$1);
        await auditEnter(tester, '이동 시간, 분', values.$2);
        await auditEnter(tester, '수면 시간, 시간', values.$3);
        await auditEnter(tester, '수면 시간, 분', values.$4);
        await auditTap(tester, '설정 저장');
        expect(store.saves, values.$5 ? 1 : 0);
        if (values.$5) {
          expect(
            store.value!.travelDuration,
            Duration(
              hours: int.parse(values.$1.trim()),
              minutes: int.parse(values.$2.trim()),
            ),
          );
          expect(
            store.value!.sleepDuration,
            Duration(
              hours: int.parse(values.$3.trim()),
              minutes: int.parse(values.$4.trim()),
            ),
          );
        }
      },
    );
  }
  for (final clock in [
    ('00', '00', true),
    ('23', '59', true),
    ('24', '00', false),
    ('23', '60', false),
    ('-1', '00', false),
    ('aa', '00', false),
  ]) {
    testWidgets('T04 시각 선택기 ${clock.$1}:${clock.$2} 검증', (tester) async {
      final store = AuditStore();
      await settings.open(tester, store);
      await pickClock(tester, 'arrival', clock.$1, clock.$2, valid: clock.$3);
      await auditTap(tester, '설정 저장');
      expect(
        store.value!.arrivalTime,
        clock.$3
            ? ClockTime(int.parse(clock.$1), int.parse(clock.$2))
            : ClockTime(9, 0),
      );
    });
  }
  testWidgets('T04 신규 입력 UI 전체 저장·재진입과 권장 모드 null 수동 시각', (tester) async {
    final store = AuditStore()..value = null;
    await settings.open(tester, store);
    await pickClock(tester, 'arrival', '00', '20');
    await auditEnter(tester, '이동 시간, 시간', '0');
    await auditEnter(tester, '이동 시간, 분', '30');
    await auditEnter(tester, '수면 시간, 시간', '8');
    await auditEnter(tester, '수면 시간, 분', '0');
    await pickClock(tester, 'start', '22', '00');
    await pickClock(tester, 'end', '02', '00');
    await auditTap(tester, '설정 저장');
    expect(store.saves, 1);
    expect(store.value!.wakeMode, WakeMode.recommended);
    expect(store.value!.manualWakeTime, isNull);
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    await auditTap(tester, '시간 설정');
    expect(find.text('저장된 설정을 수정할 수 있어요.'), findsOneWidget);
    expect(find.text('00:20'), findsOneWidget);
    expect(find.textContaining('22:00~다음 날 02:00'), findsOneWidget);
  });
  testWidgets('T04 수동 필수 검증 후 권장 모드로 바꾸면 수동 없이 저장 가능', (tester) async {
    final store = AuditStore();
    await settings.open(tester, store);
    await auditTap(tester, '직접 지정');
    await auditTap(tester, '설정 저장');
    expect(store.saves, 0);
    expect(find.text('직접 지정할 기상 시각을 선택해 주세요.'), findsOneWidget);
    await auditTap(tester, '권장 시각 사용');
    await auditTap(tester, '설정 저장');
    expect(store.saves, 1);
    expect(store.value!.manualWakeTime, isNull);
  });
  testWidgets('T04 권장보다 늦은 수동 시각과 알람을 포함하지 않는 감지 구간 허용', (tester) async {
    final store = AuditStore();
    await settings.open(tester, store);
    await auditTap(tester, '직접 지정');
    await pickClock(tester, 'manual', '12', '00');
    await auditTap(tester, '설정 저장');
    expect(store.saves, 1);
    expect(store.value!.manualWakeTime, ClockTime(12, 0));
    await auditTap(tester, '권장 시각 사용');
    await auditTap(tester, '설정 저장');
    expect(store.value!.manualWakeTime, ClockTime(12, 0));
  });
  testWidgets('T04 감지 동일 시각 거부·자정 통과·시작 포함 끝 제외', (tester) async {
    final store = AuditStore();
    await settings.open(tester, store);
    await pickClock(tester, 'end', '07', '00');
    await auditTap(tester, '설정 저장');
    expect(store.saves, 0);
    await pickClock(tester, 'start', '22', '00');
    await pickClock(tester, 'end', '02', '00');
    await auditTap(tester, '설정 저장');
    expect(store.saves, 1);
    expect(
      store.value!.containsDetectionTime(DateTime(2026, 11, 10, 22)),
      isTrue,
    );
    expect(
      store.value!.containsDetectionTime(DateTime(2026, 11, 11, 1, 59)),
      isTrue,
    );
    expect(
      store.value!.containsDetectionTime(DateTime(2026, 11, 11, 2)),
      isFalse,
    );
  });
  testWidgets('T04 분 미만 원본은 다른 필드 수정 시 그대로 보존한다', (tester) async {
    final store = AuditStore()
      ..value = auditSettings(
        travel: const Duration(microseconds: 1),
        sleep: const Duration(hours: 8, seconds: 30),
      );
    await settings.open(tester, store);
    await pickClock(tester, 'arrival', '10', '00');
    await auditTap(tester, '설정 저장');
    expect(store.saves, 1);
    expect(store.value!.travelDuration, const Duration(microseconds: 1));
    expect(store.value!.sleepDuration, const Duration(hours: 8, seconds: 30));
    await auditEnter(tester, '이동 시간, 분', '1');
    await auditTap(tester, '설정 저장');
    expect(store.value!.travelDuration, const Duration(minutes: 1));
  });
  testWidgets('T04 시각 버튼 접근성 이름이 입력 항목을 구분한다', (tester) async {
    final semantics = tester.ensureSemantics();
    await settings.open(tester, AuditStore());
    expect(find.bySemanticsLabel(RegExp('목표 도착 시각 선택')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('감지 시작 시각 선택')), findsWidgets);
    semantics.dispose();
  });
  testWidgets('T04 변경 후 이탈 취소·폐기와 저장 후 이탈', (tester) async {
    final store = AuditStore();
    await settings.open(tester, store);
    await auditEnter(tester, '이동 시간, 분', '45');
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    await auditTap(tester, '계속 수정');
    expect(find.widgetWithText(TextFormField, '45'), findsOneWidget);
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    await auditTap(tester, '저장하지 않고 나가기');
    expect(store.value!.travelDuration, const Duration(minutes: 30));
    await auditTap(tester, '시간 설정');
    await auditEnter(tester, '이동 시간, 분', '45');
    await auditTap(tester, '설정 저장');
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
  });

  for (final routinePage in [false, true]) {
    final page = routinePage ? 'T05' : 'T04';
    Future<void> navigate(WidgetTester tester) async {
      if (routinePage) {
        await tester.tap(find.text('루틴'));
        await tester.pumpAndSettle();
      }
      final button = find.text(routinePage ? '루틴 관리' : '시간 설정');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('$page 저장소 열기 실패·연속 재시도와 지연 로딩 표시', (tester) async {
      var opens = 0;
      final store = AuditStore();
      final pending = Completer<AuditStore>();
      await tester.pumpWidget(
        MorningRoutineApp(
          openStore: () async {
            opens++;
            if (opens == 1) throw StateError('open');
            return pending.future;
          },
        ),
      );
      await navigate(tester);
      final retry = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '다시 불러오기'))
          .onPressed!;
      retry();
      retry();
      await tester.pumpAndSettle();
      expect(opens, 2);
      expect(find.textContaining('불러오는 중'), findsOneWidget);
      pending.complete(store);
      await tester.pumpAndSettle();
      expect(routinePage ? store.routinesReads : store.settingsReads, 1);
      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();
      expect(store.closes, 1);
    });
    testWidgets('$page 저장소 열기 완료 전에 이탈해도 소유 저장소를 한 번 닫는다', (tester) async {
      final store = AuditStore();
      final pending = Completer<AuditStore>();
      await tester.pumpWidget(
        MorningRoutineApp(openStore: () => pending.future),
      );
      await navigate(tester);
      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();
      pending.complete(store);
      await tester.pumpAndSettle();
      expect(store.closes, 1);
      expect(tester.takeException(), isNull);
    });
    for (final borrowed in [false, true]) {
      testWidgets('$page 조회 지연 중 이탈·늦은 실패, 주입=$borrowed', (tester) async {
        final store = AuditStore();
        final gate = Completer<void>();
        if (routinePage) {
          store.routinesLoadGate = gate;
          store.library.failLoad = true;
        } else {
          store.settingsLoadGate = gate;
          store.failLoad = true;
        }
        await tester.pumpWidget(
          MorningRoutineApp(
            store: borrowed ? store : null,
            openStore: () async => store,
          ),
        );
        await navigate(tester);
        await tester.tap(find.byTooltip('뒤로'));
        await tester.pumpAndSettle();
        gate.complete();
        await tester.pumpAndSettle();
        expect(store.closes, borrowed ? 0 : 1);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('$page 작은 가로 화면·큰 글자에서 조회 오류·재시도 접근', (tester) async {
      tester.view.physicalSize = const Size(640, 320);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = AuditStore()..failLoad = true;
      store.library.failLoad = true;
      await tester.pumpWidget(MorningRoutineApp(store: store));
      await navigate(tester);
      await tester.ensureVisible(find.text('다시 불러오기'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('T04 저장 지연 중 뒤로가기·편집·연속 저장 차단과 실패 후 복구', (tester) async {
    final store = AuditStore()..gate = Completer<void>();
    await settings.open(tester, store);
    await tester.ensureVisible(find.text('설정 저장'));
    final save = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    save();
    save();
    await tester.pump();
    expect(store.saves, 1);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
      isFalse,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    store.failSave = true;
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('설정을 저장했어요.'), findsNothing);
    expect(find.text('다시 저장'), findsOneWidget);
    store.gate = null;
    store.failSave = false;
    await auditTap(tester, '다시 저장');
    expect(store.saves, 2);
  });
  testWidgets('T04 시각 선택 연속 요청은 선택기 하나만 연다', (tester) async {
    await settings.open(tester, AuditStore());
    final button = find.byKey(const ValueKey('time-arrival'));
    await tester.ensureVisible(button);
    final open = tester.widget<OutlinedButton>(button).onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await auditTap(tester, '취소');
  });
  testWidgets('T05 수정 후 전체시간 오류는 단계 삭제로 해결하면 즉시 사라진다', (tester) async {
    final store = AuditStore();
    store.library.routines['routine-old'] = routines.sample();
    await routines.openLibrary(tester, store);
    await auditTap(tester, '등교');
    await auditEnter(tester, '1단계 예상 시간', '1440');
    await auditTap(tester, '루틴 저장');
    expect(find.text('루틴 전체 예상 시간은 24시간을 넘을 수 없어요.'), findsOneWidget);
    await routines.icon(tester, '2단계 삭제');
    expect(find.text('루틴 전체 예상 시간은 24시간을 넘을 수 없어요.'), findsNothing);
  });
  testWidgets('T05 오류 숫자는 예상 시간 합계에서 제외한다', (tester) async {
    final store = AuditStore();
    store.library.routines['routine-old'] = routines.sample();
    await routines.openLibrary(tester, store);
    await auditTap(tester, '등교');
    await auditEnter(tester, '1단계 예상 시간', '+20');
    expect(find.textContaining('총 예상 시간: 15분'), findsOneWidget);
  });
  testWidgets('T05 매우 긴 루틴명과 큰 글자에서 삭제 확인창 스크롤·취소 가능', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = AuditStore();
    final name = '아침🌅' * 60;
    store.library.routines['r'] = Routine(
      id: 'r',
      name: name,
      steps: routines.sample().steps,
    );
    await routines.openLibrary(tester, store);
    await routines.icon(tester, '$name 삭제');
    await auditTap(tester, '취소');
    expect(store.library.deletes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('T04 작은 화면·큰 글자·키보드에서 입력과 오류 수정 후 저장', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = AuditStore();
    await settings.open(tester, store);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await auditEnter(tester, '이동 시간, 분', 'bad');
    await auditTap(tester, '설정 저장');
    expect(store.saves, 0);
    await auditEnter(tester, '이동 시간, 분', '45');
    await auditTap(tester, '설정 저장');
    expect(store.saves, 1);
    expect(tester.takeException(), isNull);
  });
}
