enum WakeMode { recommended, manual }

enum WakeSource { screenOn, manual, test }

enum WakeStatus { pending, confirmed, cancelled }

enum StepStatus { pending, active, completed, skipped, interrupted }

enum RunStatus { running, completed, stopped }

void requireText(String value, String field) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, field);
}

void requireDuration(Duration value, String field, {bool allowZero = false}) {
  if (value < Duration.zero || (!allowZero && value == Duration.zero)) {
    throw ArgumentError.value(value, field);
  }
  if (value > const Duration(days: 1)) {
    throw ArgumentError.value(value, field, '24시간을 초과할 수 없습니다.');
  }
}

class ClockTime {
  ClockTime(this.hour, this.minute) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw ArgumentError('시각은 00:00부터 23:59 사이여야 합니다.');
    }
  }

  factory ClockTime.fromMinutes(int value) {
    if (value < 0 || value >= 1440) throw ArgumentError.value(value);
    return ClockTime(value ~/ 60, value % 60);
  }

  final int hour;
  final int minute;
  int get minutes => hour * 60 + minute;

  DateTime on(DateTime day) => day.isUtc
      ? DateTime.utc(day.year, day.month, day.day, hour, minute)
      : DateTime(day.year, day.month, day.day, hour, minute);

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.minutes == minutes;
  @override
  int get hashCode => minutes.hashCode;
  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class AppSettings {
  AppSettings({
    required this.arrivalTime,
    required this.travelDuration,
    required this.sleepDuration,
    required this.wakeMode,
    required this.detectionStart,
    required this.detectionEnd,
    this.manualWakeTime,
  }) {
    requireDuration(travelDuration, 'travelDuration', allowZero: true);
    requireDuration(sleepDuration, 'sleepDuration');
    if (wakeMode == WakeMode.manual && manualWakeTime == null) {
      throw ArgumentError('수동 기상 시각이 필요합니다.');
    }
    if (detectionStart == detectionEnd) {
      throw ArgumentError('감지 시작과 종료 시각은 달라야 합니다.');
    }
  }

  final ClockTime arrivalTime;
  final Duration travelDuration;
  final Duration sleepDuration;
  final WakeMode wakeMode;
  final ClockTime? manualWakeTime;
  final ClockTime detectionStart;
  final ClockTime detectionEnd;

  bool containsDetectionTime(DateTime time) {
    final value = time.hour * 60 + time.minute;
    final start = detectionStart.minutes;
    final end = detectionEnd.minutes;
    return start < end
        ? value >= start && value < end
        : value >= start || value < end;
  }
}

class RoutineStep {
  RoutineStep({required this.id, required this.name, required this.expected}) {
    requireText(id, 'id');
    requireText(name, 'name');
    requireDuration(expected, 'expected');
  }
  final String id;
  final String name;
  final Duration expected;
}

class Routine {
  Routine({
    required this.id,
    required this.name,
    required List<RoutineStep> steps,
  }) : steps = List.unmodifiable(steps) {
    requireText(id, 'id');
    requireText(name, 'name');
    if (steps.isEmpty ||
        steps.map((s) => s.id).toSet().length != steps.length) {
      throw ArgumentError('루틴에는 고유한 ID를 가진 단계가 필요합니다.');
    }
    requireDuration(expected, 'routine.expected');
  }
  final String id;
  final String name;
  final List<RoutineStep> steps;
  Duration get expected =>
      steps.fold(Duration.zero, (sum, step) => sum + step.expected);
}

class WakeRecord {
  WakeRecord({
    required this.id,
    required this.observedAt,
    required this.source,
    required this.status,
    this.decidedAt,
    this.wakeAt,
  }) {
    requireText(id, 'id');
    if (decidedAt != null && decidedAt!.isBefore(observedAt)) {
      throw ArgumentError('판단 시각은 감지 시각보다 빠를 수 없습니다.');
    }
    if (status == WakeStatus.pending && (decidedAt != null || wakeAt != null)) {
      throw ArgumentError('미확인 후보에 확정 정보가 있습니다.');
    }
    if (status != WakeStatus.pending && decidedAt == null) {
      throw ArgumentError('확인 또는 취소 시각이 필요합니다.');
    }
    if ((status == WakeStatus.confirmed) != (wakeAt != null)) {
      throw ArgumentError('확정된 기록에만 기상 시각이 필요합니다.');
    }
    if (wakeAt != null && wakeAt!.isAfter(decidedAt!)) {
      throw ArgumentError('기상 시각은 확인 시각보다 늦을 수 없습니다.');
    }
  }
  final String id;
  final DateTime observedAt;
  final WakeSource source;
  final WakeStatus status;
  final DateTime? decidedAt;
  final DateTime? wakeAt;
}

class StepExecution {
  StepExecution({
    required this.step,
    required this.status,
    this.startedAt,
    this.endedAt,
  }) {
    if (endedAt != null &&
        (startedAt == null || endedAt!.isBefore(startedAt!))) {
      throw ArgumentError('단계 종료 시각이 유효하지 않습니다.');
    }
    if (status == StepStatus.pending &&
        (startedAt != null || endedAt != null)) {
      throw ArgumentError('대기 단계에 실행 시각이 있습니다.');
    }
    if (status != StepStatus.pending && startedAt == null) {
      throw ArgumentError('시작 시각이 필요합니다.');
    }
    if ((status == StepStatus.completed ||
            status == StepStatus.skipped ||
            status == StepStatus.interrupted) &&
        endedAt == null) {
      throw ArgumentError('종료 시각이 필요합니다.');
    }
    if (status == StepStatus.active && endedAt != null) {
      throw ArgumentError('진행 중인 단계에 종료 시각이 있습니다.');
    }
  }
  final RoutineStep step;
  final StepStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  Duration? get actual => endedAt?.difference(startedAt!);
}

class RoutineRun {
  RoutineRun({
    required this.id,
    required this.routineId,
    required this.routineName,
    required this.startedAt,
    required this.updatedAt,
    required this.status,
    required List<StepExecution> steps,
    this.endedAt,
    this.wakeRecordId,
    this.revision = 0,
  }) : steps = List.unmodifiable(steps) {
    requireText(id, 'id');
    requireText(routineId, 'routineId');
    requireText(routineName, 'routineName');
    if (revision < 0 ||
        updatedAt.isBefore(startedAt) ||
        (endedAt != null && endedAt!.isBefore(startedAt))) {
      throw ArgumentError('실행 기록의 시각 또는 버전이 유효하지 않습니다.');
    }
    if ((status == RunStatus.running) != (endedAt == null)) {
      throw ArgumentError('실행 상태와 종료 시각이 일치하지 않습니다.');
    }
    if (steps.isEmpty ||
        steps.map((s) => s.step.id).toSet().length != steps.length) {
      throw ArgumentError('고유한 실행 단계가 필요합니다.');
    }
    final active = steps.where((s) => s.status == StepStatus.active).length;
    if ((status == RunStatus.running && active != 1) ||
        (status != RunStatus.running && active != 0)) {
      throw ArgumentError('진행 중인 단계 수가 실행 상태와 일치하지 않습니다.');
    }
    if (status == RunStatus.completed &&
        steps.any(
          (s) =>
              s.status != StepStatus.completed &&
              s.status != StepStatus.skipped,
        )) {
      throw ArgumentError('완료 실행에 미처리 단계가 있습니다.');
    }
  }
  final String id;
  final String routineId;
  final String routineName;
  final String? wakeRecordId;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? endedAt;
  final RunStatus status;
  final List<StepExecution> steps;
  final int revision;
  StepExecution? get activeStep {
    for (final step in steps) {
      if (step.status == StepStatus.active) return step;
    }
    return null;
  }
}

class DailyPlan {
  const DailyPlan({
    required this.arrivalAt,
    required this.departureAt,
    required this.recommendedWakeAt,
    required this.alarmAt,
    required this.bedtimeAt,
    required this.preparation,
  });
  final DateTime arrivalAt;
  final DateTime departureAt;
  final DateTime recommendedWakeAt;
  final DateTime alarmAt;
  final DateTime bedtimeAt;
  final Duration preparation;
}
