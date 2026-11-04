import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/models.dart';

void main() {
  final start = DateTime.utc(2026, 11, 4, 7);
  final end = start.add(const Duration(minutes: 10));
  RoutineStep step(String id) =>
      RoutineStep(id: id, name: id, expected: const Duration(minutes: 10));
  RoutineRun stopped(List<StepExecution> steps, {DateTime? at}) => RoutineRun(
    id: 'run',
    routineId: 'routine',
    routineName: '아침',
    startedAt: start,
    updatedAt: at ?? end,
    endedAt: at ?? end,
    status: RunStatus.stopped,
    steps: steps,
  );

  group('중단 스냅샷 계약', () {
    test('완료·중단·대기 순서와 중단 시각을 보존한다', () {
      final boundary = start.add(const Duration(minutes: 5));
      final run = stopped([
        StepExecution(
          step: step('a'),
          status: StepStatus.completed,
          startedAt: start,
          endedAt: boundary,
        ),
        StepExecution(
          step: step('b'),
          status: StepStatus.interrupted,
          startedAt: boundary,
          endedAt: end,
        ),
        StepExecution(step: step('c'), status: StepStatus.pending),
      ]);
      expect(run.activeStep, isNull);
      expect(run.steps[1].endedAt, run.endedAt);
      expect(run.steps.last.startedAt, isNull);
    });

    test('모든 단계가 대기 중인 중단 기록을 거부한다', () {
      expect(
        () => stopped([
          StepExecution(step: step('a'), status: StepStatus.pending),
        ]),
        throwsArgumentError,
      );
    });

    test('모든 단계가 완료된 중단 기록을 거부한다', () {
      expect(
        () => stopped([
          StepExecution(
            step: step('a'),
            status: StepStatus.completed,
            startedAt: start,
            endedAt: end,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('완료 단계 다음에 대기만 있는 중단 기록을 거부한다', () {
      expect(
        () => stopped([
          StepExecution(
            step: step('a'),
            status: StepStatus.completed,
            startedAt: start,
            endedAt: end,
          ),
          StepExecution(step: step('b'), status: StepStatus.pending),
        ]),
        throwsArgumentError,
      );
    });

    test('중단 단계와 전체 중단 시각의 불일치를 거부한다', () {
      expect(
        () => stopped([
          StepExecution(
            step: step('a'),
            status: StepStatus.interrupted,
            startedAt: start,
            endedAt: end.subtract(const Duration(seconds: 1)),
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('시작 즉시 중단해 경과가 0인 기록도 보존한다', () {
      final run = stopped([
        StepExecution(
          step: step('a'),
          status: StepStatus.interrupted,
          startedAt: start,
          endedAt: start,
        ),
      ], at: start);
      expect(run.steps.single.actual, Duration.zero);
    });

    test('종료 뒤 갱신 시각을 바꾸는 사후 편집을 거부한다', () {
      expect(
        () => RoutineRun(
          id: 'run',
          routineId: 'routine',
          routineName: '아침',
          startedAt: start,
          updatedAt: end.add(const Duration(minutes: 1)),
          endedAt: end,
          status: RunStatus.completed,
          steps: [
            StepExecution(
              step: step('a'),
              status: StepStatus.completed,
              startedAt: start,
              endedAt: end,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  final arrival = DateTime.utc(2026, 11, 4, 9);
  final departure = DateTime.utc(2026, 11, 4, 8, 30);
  final wake = DateTime.utc(2026, 11, 4, 7, 30);
  DailyPlan plan({
    DateTime? arrivalAt,
    DateTime? departureAt,
    DateTime? recommendedWakeAt,
    DateTime? alarmAt,
    DateTime? bedtimeAt,
    Duration preparation = const Duration(hours: 1),
  }) => DailyPlan(
    arrivalAt: arrivalAt ?? arrival,
    departureAt: departureAt ?? departure,
    recommendedWakeAt: recommendedWakeAt ?? wake,
    alarmAt: alarmAt ?? wake,
    bedtimeAt: bedtimeAt ?? wake.subtract(const Duration(hours: 8)),
    preparation: preparation,
  );

  group('계획 시간 계약', () {
    test('음수·0·24시간 초과 준비 시간을 거부한다', () {
      for (final duration in [
        const Duration(minutes: -1),
        Duration.zero,
        const Duration(days: 1, seconds: 1),
      ]) {
        expect(() => plan(preparation: duration), throwsArgumentError);
      }
    });

    test('도착보다 늦은 출발을 거부한다', () {
      expect(
        () => plan(arrivalAt: departure.subtract(const Duration(minutes: 1))),
        throwsArgumentError,
      );
    });

    test('권장 기상·준비 시간·출발의 불일치를 거부한다', () {
      expect(
        () => plan(recommendedWakeAt: wake.add(const Duration(minutes: 1))),
        throwsArgumentError,
      );
    });

    test('기상 이후 또는 같은 시각의 취침을 거부한다', () {
      expect(() => plan(bedtimeAt: wake), throwsArgumentError);
      expect(
        () => plan(bedtimeAt: wake.add(const Duration(minutes: 1))),
        throwsArgumentError,
      );
    });

    test('도착보다 늦은 수동 알람도 보존한다', () {
      final manual = DateTime.utc(2026, 11, 4, 10);
      final result = plan(
        alarmAt: manual,
        bedtimeAt: manual.subtract(const Duration(hours: 8)),
      );
      expect(result.recommendedWakeAt, wake);
      expect(result.alarmAt, manual);
    });

    test('이동 0분과 전날 권장 기상·취침을 허용한다', () {
      final midnight = DateTime.utc(2027);
      final recommended = midnight.subtract(const Duration(hours: 1));
      final result = plan(
        arrivalAt: midnight,
        departureAt: midnight,
        recommendedWakeAt: recommended,
        alarmAt: recommended,
        bedtimeAt: recommended.subtract(const Duration(hours: 8)),
      );
      expect(result.departureAt, result.arrivalAt);
      expect(result.recommendedWakeAt.year, 2026);
    });
  });
}
