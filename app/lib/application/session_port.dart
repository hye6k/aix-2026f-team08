import '../domain/models.dart';
import '../domain/ports.dart';

/// 참조하는 기록과 같은 트랜잭션으로 저장할 활성 회차 식별자.
class SessionCheckpoint {
  SessionCheckpoint({
    required this.revision,
    required this.routineId,
    required this.arrivalDay,
    this.wakeId,
    this.runId,
    this.cancellationPending = false,
    this.alarmUpdatePending = false,
    this.alarmPendingAt,
  }) {
    if (revision < 0) throw ArgumentError('세션 버전은 음수일 수 없습니다.');
    if ((!alarmUpdatePending && alarmPendingAt != null) ||
        (alarmUpdatePending && cancellationPending)) {
      throw ArgumentError('알람 동기화 대기 정보가 올바르지 않습니다.');
    }
    requireText(routineId, 'routineId');
    if (wakeId != null) requireText(wakeId!, 'wakeId');
    if (runId != null) requireText(runId!, 'runId');
    if (cancellationPending && wakeId == null) {
      throw ArgumentError('취소 대기에는 기상 기록이 필요합니다.');
    }
  }
  final int revision;
  final String routineId;
  final DateTime arrivalDay;
  final String? wakeId;
  final String? runId;
  final bool cancellationPending;
  final bool alarmUpdatePending;

  /// 동기화 대기 중 null이면 예약 취소, 값이 있으면 해당 시각 예약.
  final DateTime? alarmPendingAt;
}

abstract interface class SessionStore implements RoutineStore {
  Future<SessionCheckpoint?> loadSession();

  /// 기록 저장 실패 시 설정과 활성 참조도 함께 롤백해야 한다.
  Future<void> commitSession(
    SessionCheckpoint checkpoint, {
    AppSettings? settings,
    Routine? routine,
    WakeRecord? wake,
    RoutineRun? run,
  });
}
