import 'models.dart';

class RoutineEngine {
  const RoutineEngine();

  RoutineRun start({
    required String id,
    required Routine routine,
    required DateTime at,
    String? confirmedWakeRecordId,
    RoutineRun? existing,
  }) {
    if (existing != null && existing.id == id) {
      return existing;
    }
    if (existing?.status == RunStatus.running) {
      throw StateError('이미 실행 중인 루틴이 있습니다.');
    }
    return RoutineRun(
      id: id,
      routineId: routine.id,
      routineName: routine.name,
      startedAt: at,
      updatedAt: at,
      status: RunStatus.running,
      wakeRecordId: confirmedWakeRecordId,
      steps: [
        for (var i = 0; i < routine.steps.length; i++)
          StepExecution(
            step: routine.steps[i],
            status: i == 0 ? StepStatus.active : StepStatus.pending,
            startedAt: i == 0 ? at : null,
          ),
      ],
    );
  }

  RoutineRun complete(
    RoutineRun run, {
    required String stepId,
    required DateTime at,
  }) => _advance(run, stepId, at, StepStatus.completed);
  RoutineRun skip(
    RoutineRun run, {
    required String stepId,
    required DateTime at,
  }) => _advance(run, stepId, at, StepStatus.skipped);

  RoutineRun _advance(
    RoutineRun run,
    String stepId,
    DateTime at,
    StepStatus status,
  ) {
    final index = run.steps.indexWhere((s) => s.step.id == stepId);
    if (index == -1) {
      throw ArgumentError.value(stepId, 'stepId');
    }
    final previous = run.steps[index];
    // 같은 단계의 재전송은 다음 단계를 진행시키지 않는다.
    if (previous.status == StepStatus.completed ||
        previous.status == StepStatus.skipped) {
      return run;
    }
    if (run.status != RunStatus.running ||
        previous.status != StepStatus.active) {
      throw StateError('현재 진행 단계만 처리할 수 있습니다.');
    }
    _checkTime(run, at);
    final steps = [...run.steps];
    steps[index] = StepExecution(
      step: previous.step,
      status: status,
      startedAt: previous.startedAt,
      endedAt: at,
    );
    final finished = index == steps.length - 1;
    if (!finished) {
      steps[index + 1] = StepExecution(
        step: steps[index + 1].step,
        status: StepStatus.active,
        startedAt: at,
      );
    }
    return _copy(
      run,
      steps: steps,
      at: at,
      status: finished ? RunStatus.completed : RunStatus.running,
      endedAt: finished ? at : null,
    );
  }

  RoutineRun stop(RoutineRun run, {required DateTime at}) {
    if (run.status != RunStatus.running) {
      return run;
    }
    _checkTime(run, at);
    final steps = [
      for (final s in run.steps)
        if (s.status == StepStatus.active)
          StepExecution(
            step: s.step,
            status: StepStatus.interrupted,
            startedAt: s.startedAt,
            endedAt: at,
          )
        else
          s,
    ];
    return _copy(
      run,
      steps: steps,
      at: at,
      status: RunStatus.stopped,
      endedAt: at,
    );
  }

  Duration elapsed(RoutineRun run, {required DateTime at}) {
    if (run.endedAt != null) {
      return run.endedAt!.difference(run.startedAt);
    }
    _checkTime(run, at);
    return at.difference(run.startedAt);
  }

  void _checkTime(RoutineRun run, DateTime at) {
    if (at.isBefore(run.updatedAt)) {
      throw ArgumentError('이전 조작보다 빠른 시각입니다. 시계 변경을 확인하세요.');
    }
  }

  RoutineRun _copy(
    RoutineRun run, {
    required List<StepExecution> steps,
    required DateTime at,
    required RunStatus status,
    DateTime? endedAt,
  }) => RoutineRun(
    id: run.id,
    routineId: run.routineId,
    routineName: run.routineName,
    wakeRecordId: run.wakeRecordId,
    startedAt: run.startedAt,
    updatedAt: at,
    endedAt: endedAt,
    status: status,
    steps: steps,
    revision: run.revision + 1,
  );
}
