import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/planning.dart';

void main() {
  final routine = Routine(
    id: 'r',
    name: '등교',
    steps: [
      RoutineStep(id: 'a', name: '씻기', expected: const Duration(minutes: 20)),
      RoutineStep(id: 'b', name: '준비', expected: const Duration(minutes: 40)),
    ],
  );
  AppSettings settings({
    int arrivalHour = 9,
    WakeMode mode = WakeMode.recommended,
    ClockTime? manual,
  }) => AppSettings(
    arrivalTime: ClockTime(arrivalHour, 0),
    travelDuration: const Duration(minutes: 40),
    sleepDuration: const Duration(hours: 8),
    wakeMode: mode,
    manualWakeTime: manual,
    detectionStart: ClockTime(5, 0),
    detectionEnd: ClockTime(10, 0),
  );

  test('09시 도착·40분 이동·60분 준비·8시간 수면의 기대값', () {
    final plan = calculateDailyPlan(
      arrivalDay: DateTime.utc(2026, 11, 1),
      settings: settings(),
      routine: routine,
    );
    expect(plan.preparation, const Duration(hours: 1));
    expect(plan.departureAt, DateTime.utc(2026, 11, 1, 8, 20));
    expect(plan.recommendedWakeAt, DateTime.utc(2026, 11, 1, 7, 20));
    expect(plan.alarmAt, plan.recommendedWakeAt);
    expect(plan.bedtimeAt, DateTime.utc(2026, 10, 31, 23, 20));
  });
  test('수동 모드는 권장 시각을 유지하면서 실제 알람·취침만 변경한다', () {
    final plan = calculateDailyPlan(
      arrivalDay: DateTime.utc(2026, 11, 1),
      settings: settings(mode: WakeMode.manual, manual: ClockTime(10, 0)),
      routine: routine,
    );
    expect(plan.recommendedWakeAt, DateTime.utc(2026, 11, 1, 7, 20));
    expect(plan.alarmAt, DateTime.utc(2026, 11, 1, 10));
    expect(plan.bedtimeAt, DateTime.utc(2026, 11, 1, 2));
  });
  test('연도 경계에서 전날 기상·취침 날짜를 보존한다', () {
    final plan = calculateDailyPlan(
      arrivalDay: DateTime.utc(2027, 1, 1),
      settings: settings(arrivalHour: 0),
      routine: routine,
    );
    expect(plan.departureAt, DateTime.utc(2026, 12, 31, 23, 20));
    expect(plan.alarmAt, DateTime.utc(2026, 12, 31, 22, 20));
    expect(plan.bedtimeAt, DateTime.utc(2026, 12, 31, 14, 20));
  });
  test('자정 계획의 수동 시각은 권장 기상 날짜에 놓는다', () {
    final plan = calculateDailyPlan(
      arrivalDay: DateTime.utc(2027, 1, 1),
      settings: settings(
        arrivalHour: 0,
        mode: WakeMode.manual,
        manual: ClockTime(23, 0),
      ),
      routine: routine,
    );
    expect(plan.alarmAt, DateTime.utc(2026, 12, 31, 23));
  });
}
