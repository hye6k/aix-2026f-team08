import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/models.dart';

void main() {
  test('시각 경계와 날짜의 UTC 속성을 보존한다', () {
    expect(ClockTime.fromMinutes(1439), ClockTime(23, 59));
    expect(() => ClockTime(24, 0), throwsArgumentError);
    expect(() => ClockTime.fromMinutes(-1), throwsArgumentError);
    expect(
      ClockTime(7, 30).on(DateTime.utc(2026, 10, 31)),
      DateTime.utc(2026, 10, 31, 7, 30),
    );
  });

  test('수동 시각 누락과 모호한 감지 구간을 거부한다', () {
    AppSettings settings({ClockTime? manual, int end = 9}) => AppSettings(
      arrivalTime: ClockTime(9, 0),
      travelDuration: Duration.zero,
      sleepDuration: const Duration(hours: 8),
      wakeMode: WakeMode.manual,
      manualWakeTime: manual,
      detectionStart: ClockTime(6, 0),
      detectionEnd: ClockTime(end, 0),
    );
    expect(() => settings(), throwsArgumentError);
    expect(
      () => settings(manual: ClockTime(7, 0), end: 6),
      throwsArgumentError,
    );
  });

  test('루틴은 단계 ID와 양수 시간을 검증하고 원본 목록 변경을 격리한다', () {
    final step = RoutineStep(
      id: 'wash',
      name: '세면',
      expected: const Duration(minutes: 10),
    );
    final source = [step];
    final routine = Routine(id: 'morning', name: '아침', steps: source);
    source.clear();
    expect(routine.steps, hasLength(1));
    expect(() => routine.steps.clear(), throwsUnsupportedError);
    expect(
      () => Routine(id: 'x', name: '아침', steps: [step, step]),
      throwsArgumentError,
    );
    expect(
      () => RoutineStep(id: 'x', name: '준비', expected: Duration.zero),
      throwsArgumentError,
    );
  });

  test('미확인 후보를 확정 기록처럼 만들 수 없다', () {
    final at = DateTime.utc(2026, 10, 31, 7);
    expect(
      () => WakeRecord(
        id: 'w',
        observedAt: at,
        source: WakeSource.screenOn,
        status: WakeStatus.pending,
        wakeAt: at,
      ),
      throwsArgumentError,
    );
    expect(
      () => WakeRecord(
        id: 'w',
        observedAt: at,
        source: WakeSource.screenOn,
        status: WakeStatus.confirmed,
        decidedAt: at,
      ),
      throwsArgumentError,
    );
  });
}
