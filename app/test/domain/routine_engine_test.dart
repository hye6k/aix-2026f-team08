import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/routine_engine.dart';

void main() {
  const engine = RoutineEngine();
  final at = DateTime.utc(2026, 11, 1, 7);
  final routine = Routine(
    id: 'r',
    name: '등교',
    steps: [
      RoutineStep(id: 'a', name: '씻기', expected: const Duration(minutes: 10)),
      RoutineStep(id: 'b', name: '준비', expected: const Duration(minutes: 20)),
    ],
  );
  RoutineRun start() => engine.start(id: 'run', routine: routine, at: at);

  test('수동 시작은 기상 확정과 분리되고 동일 시작 재전송은 실행을 복제하지 않는다', () {
    final run = start();
    expect(run.wakeRecordId, isNull);
    expect(
      engine.start(id: 'run', routine: routine, at: at, existing: run),
      same(run),
    );
    expect(
      () => engine.start(id: 'other', routine: routine, at: at, existing: run),
      throwsStateError,
    );
  });
  test('완료·건너뛰기·중복 조작이 순서와 실제 시간을 보존한다', () {
    final one = engine.complete(
      start(),
      stepId: 'a',
      at: at.add(const Duration(minutes: 12)),
    );
    expect(one.activeStep!.step.id, 'b');
    expect(one.steps.first.actual, const Duration(minutes: 12));
    expect(
      engine.complete(
        one,
        stepId: 'a',
        at: at.add(const Duration(minutes: 13)),
      ),
      same(one),
    );
    final done = engine.skip(
      one,
      stepId: 'b',
      at: at.add(const Duration(minutes: 14)),
    );
    expect(done.status, RunStatus.completed);
    expect(done.steps.last.status, StepStatus.skipped);
    expect(done.revision, 2);
    expect(engine.stop(done, at: at.add(const Duration(hours: 1))), same(done));
  });
  test('예상 시간을 넘겨도 자동 완료하지 않고 앱을 닫아 둔 시간을 반영한다', () {
    final saved = start();
    final restored = RoutineRun(
      id: saved.id,
      routineId: saved.routineId,
      routineName: saved.routineName,
      startedAt: saved.startedAt,
      updatedAt: saved.updatedAt,
      status: saved.status,
      steps: saved.steps,
      revision: saved.revision,
    );
    expect(
      engine.elapsed(restored, at: at.add(const Duration(hours: 2))),
      const Duration(hours: 2),
    );
    expect(restored.activeStep!.step.id, 'a');
    expect(restored.status, RunStatus.running);
  });
  test('중단 스냅샷은 진행 상태로 복원되지 않고 중복 종료는 멱등적이다', () {
    final stopped = engine.stop(
      start(),
      at: at.add(const Duration(minutes: 3)),
    );
    expect(stopped.status, RunStatus.stopped);
    expect(stopped.activeStep, isNull);
    expect(stopped.steps.first.status, StepStatus.interrupted);
    expect(
      engine.elapsed(stopped, at: at.add(const Duration(hours: 2))),
      const Duration(minutes: 3),
    );
    expect(
      engine.stop(stopped, at: at.add(const Duration(hours: 2))),
      same(stopped),
    );
    expect(
      () => engine.complete(stopped, stepId: 'b', at: at),
      throwsStateError,
    );
  });
  test('미래 단계 처리와 역행한 시계를 거부한다', () {
    expect(
      () => engine.complete(start(), stepId: 'b', at: at),
      throwsStateError,
    );
    expect(
      () => engine.skip(start(), stepId: 'missing', at: at),
      throwsArgumentError,
    );
    expect(
      () => engine.complete(
        start(),
        stepId: 'a',
        at: at.subtract(const Duration(seconds: 1)),
      ),
      throwsArgumentError,
    );
  });
}
