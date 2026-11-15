import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/app.dart';
import 'package:morning_routine/presentation/ux_comparison.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
      MaterialApp(
        home: MorningConceptScreen(
          now: DateTime(2026, 11, 9, 8),
          persist: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
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
    await tapText('다가오는 아침');
    expect(find.text('오늘 · 월요일 · 출근'), findsOneWidget);
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

  testWidgets('저장된 장소 좌표와 루틴이 재진입 후 복원된다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ux_location_draft_v1': jsonEncode({
        'nextId': 3,
        'places': [
          {'id': 0, 'name': '집', 'location': '집 주소', 'lat': 37.1, 'lng': 127.1},
          {
            'id': 1,
            'name': '회사',
            'location': '회사 주소',
            'lat': 37.2,
            'lng': 127.2,
          },
        ],
        'routines': [
          {
            'id': 2,
            'name': '출근',
            'origin': 0,
            'destination': 1,
            'hour': 9,
            'minute': 0,
            'days': [1],
          },
        ],
      }),
    });
    await tester.pumpWidget(
      MaterialApp(home: MorningConceptScreen(now: DateTime(2026, 11, 9, 8))),
    );
    await tester.pumpAndSettle();
    expect(find.text('오늘 · 월요일 · 출근'), findsOneWidget);
    await tester.tap(find.text('관리').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('집'));
    await tester.pumpAndSettle();
    expect(find.text('선택한 좌표: 37.100000, 127.100000'), findsOneWidget);
  });

  for (final scenario in [
    (DateTime(2026, 11, 9, 8, 59), '오늘 · 월요일 · 출근'),
    (DateTime(2026, 11, 9, 9), '내일 · 화요일 · 출근'),
    (DateTime(2026, 11, 13, 10), '11월 16일 · 월요일 · 출근'),
    (DateTime(2026, 11, 15, 23), '내일 · 월요일 · 출근'),
  ]) {
    testWidgets('가까운 예정 루틴: ${scenario.$1}', (tester) async {
      SharedPreferences.setMockInitialValues({
        'ux_location_draft_v1': jsonEncode({
          'nextId': 3,
          'places': [
            {'id': 0, 'name': '집', 'location': '주소', 'lat': null, 'lng': null},
            {
              'id': 1,
              'name': '회사',
              'location': '주소',
              'lat': 37.2,
              'lng': 127.2,
            },
          ],
          'routines': [
            {
              'id': 2,
              'name': '출근',
              'origin': 0,
              'destination': 1,
              'hour': 9,
              'minute': 0,
              'days': [1, 2, 3, 4, 5],
            },
          ],
        }),
      });
      await tester.pumpWidget(
        MaterialApp(home: MorningConceptScreen(now: scenario.$1)),
      );
      await tester.pumpAndSettle();
      expect(find.text(scenario.$2), findsOneWidget);
      expect(find.text('장소 위치를 확인해 주세요'), findsOneWidget);
      expect(find.text('아직 예측할 기록이 없어요'), findsOneWidget);
    });
  }
}
