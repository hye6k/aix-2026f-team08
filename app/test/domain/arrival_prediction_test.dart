import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/arrival_prediction.dart';

void main() {
  final predictor = ArrivalPredictor();
  final start = DateTime.utc(2026, 11, 1, 7);
  final routine = Routine(
    id: 'r',
    name: '등교',
    steps: [
      RoutineStep(id: 'a', name: '씻기', expected: const Duration(minutes: 10)),
      RoutineStep(id: 'b', name: '준비', expected: const Duration(minutes: 20)),
    ],
  );
  ArrivalPrediction predict(
    DateTime now, {
    RoutineRun? run,
    bool confirmed = false,
    DateTime? target,
  }) => predictor.calculate(
    now: now,
    targetArrival: target ?? DateTime.utc(2026, 11, 1, 8),
    travel: const Duration(minutes: 40),
    routine: routine,
    wakeConfirmed: confirmed,
    run: run,
  );

  test('후보 단계는 조건부이며 실제 기상을 확정하지 않는다', () {
    final result = predict(start);
    expect(result.arrivalAt, DateTime.utc(2026, 11, 1, 8, 10));
    expect(result.lateMinutes, 10);
    expect(result.isConditional, isTrue);
    expect(predict(start, confirmed: true).isConditional, isFalse);
  });
  test('현재 단계 경과 시간을 차감하고 초과 시 최소 잔여를 유지한다', () {
    final run = RoutineRun(
      id: 'run',
      routineId: 'r',
      routineName: '등교',
      startedAt: start,
      updatedAt: start,
      status: RunStatus.running,
      steps: [
        StepExecution(
          step: routine.steps[0],
          status: StepStatus.active,
          startedAt: start,
        ),
        StepExecution(step: routine.steps[1], status: StepStatus.pending),
      ],
    );
    expect(
      predict(
        start.add(const Duration(minutes: 3)),
        run: run,
      ).remainingPreparation,
      const Duration(minutes: 27),
    );
    expect(
      predict(
        start.add(const Duration(minutes: 20)),
        run: run,
      ).remainingPreparation,
      const Duration(minutes: 21),
    );
    expect(run.steps[0].status, StepStatus.active);
  });
  test('완료·건너뛴 단계는 잔여에서 제외하고 초 단위 지각은 올림한다', () {
    final end = start.add(const Duration(minutes: 10));
    final run = RoutineRun(
      id: 'run',
      routineId: 'r',
      routineName: '등교',
      startedAt: start,
      updatedAt: end,
      endedAt: end,
      status: RunStatus.completed,
      steps: [
        StepExecution(
          step: routine.steps[0],
          status: StepStatus.completed,
          startedAt: start,
          endedAt: end,
        ),
        StepExecution(
          step: routine.steps[1],
          status: StepStatus.skipped,
          startedAt: end,
          endedAt: end,
        ),
      ],
    );
    final result = predict(
      end,
      run: run,
      target: end.add(const Duration(minutes: 39, seconds: 59)),
    );
    expect(result.remainingPreparation, Duration.zero);
    expect(result.lateMinutes, 1);
    expect(
      predict(
        end,
        run: run,
        target: end.add(const Duration(minutes: 40)),
      ).lateMinutes,
      0,
    );
  });
  test('자정을 넘는 예상 도착 날짜를 유지한다', () {
    final result = predict(
      DateTime.utc(2026, 12, 31, 23, 30),
      target: DateTime.utc(2027, 1, 1, 0, 30),
    );
    expect(result.arrivalAt, DateTime.utc(2027, 1, 1, 0, 40));
    expect(result.lateMinutes, 10);
  });
}
