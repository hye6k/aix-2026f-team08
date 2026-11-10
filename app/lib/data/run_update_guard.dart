import '../domain/models.dart';

/// 상태 전이는 허용하되 실행 당시 데이터와 이미 끝난 단계는 보존한다.
void validateRunUpdate(RoutineRun old, RoutineRun next) {
  if (old.status != RunStatus.running ||
      next.revision <= old.revision ||
      next.id != old.id ||
      next.routineId != old.routineId ||
      next.routineName != old.routineName ||
      next.wakeRecordId != old.wakeRecordId ||
      !next.startedAt.isAtSameMomentAs(old.startedAt) ||
      next.updatedAt.isBefore(old.updatedAt) ||
      next.steps.length != old.steps.length) {
    throw StateError('종료 기록·오래된 상태·실행 당시 정보를 덮어쓸 수 없습니다.');
  }
  bool sameTime(DateTime? a, DateTime? b) =>
      a == null ? b == null : b != null && a.isAtSameMomentAs(b);
  for (var i = 0; i < old.steps.length; i++) {
    final before = old.steps[i], after = next.steps[i];
    if (before.step.id != after.step.id ||
        before.step.name != after.step.name ||
        before.step.expected != after.step.expected) {
      throw StateError('실행 당시 단계 순서와 내용을 바꿀 수 없습니다.');
    }
    if (before.status == StepStatus.completed ||
        before.status == StepStatus.skipped) {
      if (before.status != after.status ||
          !sameTime(before.startedAt, after.startedAt) ||
          !sameTime(before.endedAt, after.endedAt)) {
        throw StateError('이미 처리한 단계의 결과를 바꿀 수 없습니다.');
      }
    } else {
      if ((before.startedAt != null &&
              !sameTime(before.startedAt, after.startedAt)) ||
          (before.status == StepStatus.pending &&
              after.startedAt != null &&
              after.startedAt!.isBefore(old.updatedAt)) ||
          (after.endedAt != null && after.endedAt!.isBefore(old.updatedAt))) {
        throw StateError('단계 추적 시각을 이전 상태보다 앞당길 수 없습니다.');
      }
    }
  }
}
