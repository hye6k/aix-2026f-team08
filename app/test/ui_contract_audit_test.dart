import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/presentation/routine_screen.dart';

import 'routine_screen_test.dart' as routines;
import 'settings_screen_test.dart' as settings;

void main() {
  testWidgets('T04 저장 검증 실패 시 첫 오류가 화면에 보인다', (tester) async {
    await settings.open(tester, settings.TestStore()..value = null);
    await settings.tap(tester, '설정 저장');
    expect(find.text('목표 도착 시각을 선택해 주세요.').hitTestable(), findsOneWidget);
  });

  testWidgets('T04 미저장 변경 이탈은 확인하고 원본을 유지한다', (tester) async {
    final store = settings.TestStore();
    await settings.open(tester, store);
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.enterText(find.byType(TextFormField).first, '1');
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    expect(find.text('변경한 내용을 저장하지 않고 나갈까요?'), findsOneWidget);
    expect(store.saves, 0);
  });

  testWidgets('T05 미변경 편집 뒤로가기 연속 두 번은 목록을 넘겨 나가지 않는다', (tester) async {
    final store = routines.RoutineTestStore()
      ..routines['routine-old'] = routines.sample();
    await routines.openLibrary(tester, store);
    await routines.press(tester, '등교');
    await tester.tap(find.byTooltip('편집 취소'));
    await tester.tap(find.byTooltip('편집 취소'));
    await tester.pumpAndSettle();
    expect(find.byType(RoutineLibraryScreen), findsOneWidget);
    expect(find.byType(RoutineEditorScreen), findsNothing);
  });

  testWidgets('T05 삭제 실패 후 목록을 나가도 재시도 콜백이 폐기된 상태를 변경하지 않는다', (tester) async {
    final store = routines.RoutineTestStore()
      ..routines['routine-old'] = routines.sample();
    store.failDelete = true;
    await routines.openLibrary(tester, store);
    await routines.icon(tester, '등교 삭제');
    await routines.press(tester, '삭제');
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    if (find.text('다시 삭제').evaluate().isNotEmpty) {
      await tester.tap(find.text('다시 삭제'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    expect(store.deletes, 1);
  });

  testWidgets('T05 삭제 확인 연속 두 번은 확인창 하나만 닫는다', (tester) async {
    final store = routines.RoutineTestStore()
      ..routines['routine-old'] = routines.sample();
    await routines.openLibrary(tester, store);
    await routines.icon(tester, '등교 삭제');
    final confirm = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '삭제'))
        .onPressed!;
    confirm();
    confirm();
    await tester.pumpAndSettle();
    expect(find.byType(RoutineLibraryScreen), findsOneWidget);
    expect(store.deletes, 1);
    expect(tester.takeException(), isNull);
  });
}
