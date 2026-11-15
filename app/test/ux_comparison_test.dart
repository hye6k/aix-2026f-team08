import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/app.dart';
import 'package:morning_routine/presentation/ux_comparison.dart';

void main() {
  testWidgets('비교 모드와 기본 앱 전환', (tester) async {
    await tester.pumpWidget(const MorningRoutineApp(compareUi: true));
    await tester.tap(find.text('새 UX 시안 보기'));
    await tester.pumpAndSettle();
    expect(find.text('나의 아침을\n가볍게 준비해요'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('기존 앱 보기'));
    await tester.pumpAndSettle();
    expect(find.text('나에게 맞는 아침을 준비해요'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('두 가지 흐름을 비교해 보세요'), findsOneWidget);
  });

  testWidgets('장소 조합과 요일 배정, 오늘 적용 및 중복 방지', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MorningConceptScreen(today: 1)),
    );
    Future<void> tapText(String text) async {
      final finder = find.text(text).last;
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> addPlace(
      String name,
      String address, {
      String button = '장소 추가',
    }) async {
      await tapText(button);
      await tester.enterText(find.widgetWithText(TextField, '장소 이름'), name);
      await tester.enterText(
        find.widgetWithText(TextField, '위치 설명 또는 주소'),
        address,
      );
      await tapText('장소 저장');
    }

    await tapText('시작하기');
    await addPlace('집', '주소 1');
    await tapText('아침 루틴 만들기');
    await addPlace('회사', '주소 2', button: '새 장소 추가');
    await tester.enterText(find.widgetWithText(TextField, '루틴 이름'), '출근');
    await tapText('출발지');
    await tapText('집');
    await tapText('도착지');
    await tapText('회사');
    await tapText('월');
    await tapText('루틴 저장');
    expect(find.text('출근'), findsOneWidget);
    await tapText('오늘');
    expect(find.text('오늘의 루틴 · 출근'), findsOneWidget);
    expect(find.text('집 → 회사'), findsOneWidget);
    expect(find.text('아직 예측할 기록이 없어요'), findsOneWidget);
    await tapText('관리');
    await tapText('아침 루틴 만들기');
    await tapText('월');
    expect(find.text('월요일은 ‘출근’ 루틴에 적용 중이에요.'), findsOneWidget);
  });

  testWidgets('비교 플래그가 없으면 기존 앱이 바로 열린다', (tester) async {
    await tester.pumpWidget(const MorningRoutineApp());
    expect(find.text('나에게 맞는 아침을 준비해요'), findsOneWidget);
    expect(find.text('두 가지 흐름을 비교해 보세요'), findsNothing);
  });
}
