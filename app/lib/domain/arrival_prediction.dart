import 'models.dart';

class ArrivalPrediction {
  const ArrivalPrediction({
    required this.arrivalAt,
    required this.remainingPreparation,
    required this.lateMinutes,
    required this.isConditional,
  });
  final DateTime arrivalAt;
  final Duration remainingPreparation;
  final int lateMinutes;
  final bool isConditional;
}

/// 남은 준비를 마치고 즉시 출발한다고 가정하며 실제 출발·도착은 추적하지 않는다.
class ArrivalPredictor {
  ArrivalPredictor({this.activeStepMinimum = const Duration(minutes: 1)}) {
    requireDuration(activeStepMinimum, 'activeStepMinimum');
  }
  final Duration activeStepMinimum;

  ArrivalPrediction calculate({
    required DateTime now,
    required DateTime targetArrival,
    required Duration travel,
    required Routine routine,
    required bool wakeConfirmed,
    RoutineRun? run,
  }) {
    requireDuration(travel, 'travel', allowZero: true);
    var remaining = routine.expected;
    if (run != null) {
      if (run.routineId != routine.id || run.status == RunStatus.stopped) {
        throw StateError('이 루틴의 도착 예상 대상 실행이 아닙니다.');
      }
      // 저장된 실행 갱신 시각과 비교한다. 이전 계산 시각은 저장하지 않는다.
      if (now.isBefore(run.updatedAt)) {
        throw ArgumentError('실행 기록보다 빠른 현재 시각입니다.');
      }
      remaining = Duration.zero;
      for (final execution in run.steps) {
        if (execution.status == StepStatus.pending) {
          remaining += execution.step.expected;
        } else if (execution.status == StepStatus.active) {
          final budget =
              execution.step.expected - now.difference(execution.startedAt!);
          // 남은 예상이 1분 미만이면 초과 전이라도 최소값을 적용한다.
          remaining += budget < activeStepMinimum ? activeStepMinimum : budget;
        }
      }
    }
    final arrival = now.add(remaining).add(travel);
    final late = arrival.difference(targetArrival).inMicroseconds;
    const minute = Duration.microsecondsPerMinute;
    return ArrivalPrediction(
      arrivalAt: arrival,
      remainingPreparation: remaining,
      lateMinutes: late <= 0 ? 0 : (late + minute - 1) ~/ minute,
      isConditional: !wakeConfirmed,
    );
  }
}
