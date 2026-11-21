import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/app.dart';
import 'package:morning_routine/presentation/location_picker.dart';
import 'package:morning_routine/presentation/ux_comparison.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('새 화면에서 시작하고 설정의 개발자 옵션에서 기존 화면을 연다', (tester) async {
    await tester.pumpWidget(const MorningRoutineApp(compareUi: true));
    await tester.pumpAndSettle();
    expect(find.text('나의 아침을\n가볍게 준비해요'), findsOneWidget);
    expect(find.text('새 UX 시안 보기'), findsNothing);
    await tester.ensureVisible(find.text('시작하기'));
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('개발자 옵션'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('개발자 옵션'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기존 앱 화면 열기'));
    await tester.pumpAndSettle();
    expect(find.text('나에게 맞는 아침을 준비해요'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('개발자 옵션'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('장소 관리'), findsOneWidget);
  });

  testWidgets('장소 조합과 요일 배정, 오늘 적용 및 중복 방지', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
      await tapText('지도에서 선택');
      final picker = tester.element(find.byType(LocationPickerScreen));
      Navigator.of(picker).pop(SelectedLocation(37.5, 127.0, address));
      await tester.pumpAndSettle();
      expect(find.text(address), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '장소 이름'), name);
      await tapText('장소 저장');
    }

    await tapText('시작하기');
    expect(find.text('장소 관리'), findsNothing);
    await tapText('설정');
    await tapText('장소 관리');
    await addPlace('집', '주소 1');
    expect(find.text('집'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText('관리');
    await tapText('아침 루틴 만들기');
    await tester.enterText(find.widgetWithText(TextField, '루틴 이름'), '출근');
    await tapText('출발지');
    await tapText('집');
    await tapText('도착지');
    await addPlace('회사', '주소 2', button: '새 장소 추가');
    expect(find.text('회사'), findsOneWidget);
    expect(find.text('도착 마감 시각'), findsNothing);
    await tapText('루틴 저장');
    expect(find.textContaining('일정 미설정'), findsOneWidget);
    await tapText('일정 설정');
    await tapText('월');
    await tapText('일정 저장');
    expect(find.text('기상 시각을 정해 주세요.'), findsOneWidget);
    await tapText('시간 정하기');
    await tapText('OK');
    await tapText('일정 저장');
    expect(find.text('출근'), findsOneWidget);
    await tapText('홈');
    expect(find.text('오늘 · 월요일'), findsOneWidget);
    expect(find.text('회사'), findsOneWidget);
    expect(find.text('집 → 회사'), findsNothing);
    expect(find.text('기상 시간 변경'), findsOneWidget);
    await tapText('관리');
    await tapText('아침 루틴 만들기');
    await tester.enterText(find.widgetWithText(TextField, '루틴 이름'), '다른 루틴');
    await tapText('출발지');
    await tapText('집');
    await tapText('도착지');
    await tapText('회사');
    await tapText('루틴 저장');
    await tapText('일정 설정');
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
    expect(find.text('오늘 · 월요일'), findsOneWidget);
    await tester.tap(find.text('설정').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('장소 관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('집'));
    await tester.pumpAndSettle();
    expect(find.text('집 주소'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('예시 데이터의 완료·실패는 내일로 전환하고 원본은 보존한다', (tester) async {
    final original = jsonEncode({
      'nextId': 3,
      'places': [
        {'id': 0, 'name': '내 집', 'location': '주소', 'lat': 37.1, 'lng': 127.1},
        {'id': 1, 'name': '내 회사', 'location': '주소', 'lat': 37.2, 'lng': 127.2},
      ],
      'routines': [
        {
          'id': 2,
          'name': '내 출근',
          'origin': 0,
          'destination': 1,
          'hour': 9,
          'minute': 0,
          'days': [1],
        },
      ],
    });
    SharedPreferences.setMockInitialValues({'ux_location_draft_v1': original});
    await tester.pumpWidget(
      MaterialApp(
        home: MorningConceptScreen(
          now: DateTime(2026, 11, 9, 10),
          developerOptions: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tapVisible(String label) async {
      final target = find.text(label).last;
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tapVisible('설정');
    await tapVisible('개발자 옵션');
    await tapVisible('대학생 예시 데이터 불러오기');
    expect(find.text('오늘 · 월요일'), findsOneWidget);
    await tapVisible('기록');
    expect(find.textContaining('예시 데이터 · 최근 60일'), findsOneWidget);
    expect(find.textContaining('오전 강의'), findsWidgets);
    expect(find.textContaining('전공 실습'), findsWidgets);
    expect(find.textContaining('주말 아르바이트'), findsWidgets);
    await tapVisible('2026.11');
    expect(find.textContaining('2026년 10월'), findsNothing);
    await tapVisible('2026.10');
    expect(find.textContaining('2026년 11월'), findsNothing);
    await tapVisible('전체');
    await tester.ensureVisible(find.text('자세히 보기').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('자세히 보기').first);
    await tester.pumpAndSettle();
    expect(find.text('예시 기록'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tapVisible('설정');
    await tapVisible('개발자 옵션');
    await tapVisible('완료');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tapVisible('홈');
    expect(find.text('내일 · 화요일'), findsOneWidget);
    expect(find.text('지금 잠들면 기상 시각까지 21시간 0분 남아요.'), findsOneWidget);
    await tapVisible('설정');
    await tapVisible('개발자 옵션');
    await tapVisible('실패');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tapVisible('홈');
    expect(find.text('내일 · 화요일'), findsOneWidget);
    await tapVisible('설정');
    await tapVisible('개발자 옵션');
    await tapVisible('원래 데이터로 돌아가기');
    expect(
      (await SharedPreferences.getInstance()).getString('ux_location_draft_v1'),
      original,
    );
    await tapVisible('홈');
    expect(find.text('내 회사'), findsOneWidget);
  });

  testWidgets('직접 정한 기상 시각을 저장하고 실제 알람과 구분한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'ux_location_draft_v1': jsonEncode({
        'nextId': 3,
        'places': [
          {'id': 0, 'name': '집', 'location': '주소', 'lat': 37.1, 'lng': 127.1},
          {'id': 1, 'name': '회사', 'location': '주소', 'lat': 37.2, 'lng': 127.2},
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
    expect(find.text('기상 알람은 아직 연결되지 않았어요.'), findsOneWidget);
    await tester.ensureVisible(find.text('기상 시간 정하기'));
    await tester.tap(find.text('기상 시간 정하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final data = jsonDecode(
      (await SharedPreferences.getInstance()).getString(
        'ux_location_draft_v1',
      )!,
    ) as Map<String, dynamic>;
    expect(data['routines'][0]['wakeHour'], 7);
    expect(data['routines'][0]['wakeMinute'], 0);
    expect(find.text('기상 시간 변경'), findsOneWidget);
    expect(find.text('설정한 기상 시각이 지났어요.'), findsOneWidget);
  });

  testWidgets('같은 경로의 기록 3건으로 출발 시각을 계산한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final morning = DateTime(2026, 11, 9, 8);
    SharedPreferences.setMockInitialValues({
      'ux_location_draft_v1': jsonEncode({
        'nextId': 3,
        'places': [
          {'id': 0, 'name': '집', 'location': '주소'},
          {'id': 1, 'name': '학교', 'location': '주소'},
        ],
        'routines': [
          {
            'id': 2,
            'name': '등교',
            'origin': 0,
            'destination': 1,
            'hour': 9,
            'minute': 0,
            'days': [1],
          },
        ],
      }),
      'ux_trip_records_v1': jsonEncode([
        for (final (day, minutes) in [(2, 30), (3, 35), (4, 90)])
          {
            'routineId': 2,
            'name': '등교',
            'origin': 0,
            'destination': 1,
            'departure': DateTime(2026, 11, day, 8).millisecondsSinceEpoch,
            'arrival': DateTime(
              2026,
              11,
              day,
              8,
              minutes,
            ).millisecondsSinceEpoch,
          },
      ]),
    });
    await tester.pumpWidget(
      MaterialApp(home: MorningConceptScreen(now: morning)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('08:25까지 출발 권장 · 평소 35분'), findsOneWidget);
    await tester.tap(find.text('출발 기록'));
    await tester.pumpAndSettle();
    expect(find.text('도착 기록'), findsOneWidget);
  });

  for (final scenario in [
    (DateTime(2026, 11, 9, 8, 59), '오늘 · 월요일'),
    (DateTime(2026, 11, 9, 10), '오늘 · 월요일'),
    (DateTime(2026, 11, 13, 10), '오늘 · 금요일'),
    (DateTime(2026, 11, 14, 10), '오늘과 내일은 쉬는 날이에요'),
    (DateTime(2026, 11, 15, 23), '내일 · 월요일'),
  ]) {
    testWidgets('오늘·내일 홈: ${scenario.$1}', (tester) async {
      SharedPreferences.setMockInitialValues({
        'ux_location_draft_v1': jsonEncode({
          'nextId': 3,
          'places': [
            {'id': 0, 'name': '집', 'location': '주소', 'lat': 37.1, 'lng': 127.1},
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
    });
  }
}
