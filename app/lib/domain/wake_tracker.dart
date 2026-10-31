import 'models.dart';

class WakeTracker {
  WakeTracker({
    this.deduplicationWindow = const Duration(minutes: 1),
    this.rearmDelay = const Duration(minutes: 1),
  }) {
    if (deduplicationWindow.isNegative || rearmDelay.isNegative) {
      throw ArgumentError('시간 간격은 음수일 수 없습니다.');
    }
  }
  final Duration deduplicationWindow;
  final Duration rearmDelay;

  /// previous는 동일한 계획 회차의 마지막 기록이다. 다른 날짜 회차는 호출자가 분리한다.
  WakeRecord? detect({
    required String id,
    required DateTime at,
    required AppSettings settings,
    WakeSource source = WakeSource.screenOn,
    WakeRecord? previous,
  }) {
    if (source == WakeSource.manual) {
      throw ArgumentError('수동 기상은 recordManual을 사용합니다.');
    }
    if (!settings.containsDetectionTime(at)) return null;
    if (previous != null) {
      if (at.isBefore(previous.observedAt)) return null;
      if (previous.status == WakeStatus.confirmed ||
          previous.status == WakeStatus.pending) {
        return previous;
      }
      if (at.isBefore(previous.observedAt.add(deduplicationWindow)) ||
          at.isBefore(previous.decidedAt!.add(rearmDelay))) {
        return null;
      }
    }
    return WakeRecord(
      id: id,
      observedAt: at,
      source: source,
      status: WakeStatus.pending,
    );
  }

  WakeRecord confirm(
    WakeRecord record, {
    required DateTime at,
    DateTime? wakeAt,
  }) {
    if (record.status == WakeStatus.confirmed) return record;
    if (record.status == WakeStatus.cancelled) {
      throw StateError('취소된 후보는 확정할 수 없습니다.');
    }
    return WakeRecord(
      id: record.id,
      observedAt: record.observedAt,
      source: record.source,
      status: WakeStatus.confirmed,
      decidedAt: at,
      wakeAt: wakeAt ?? record.observedAt,
    );
  }

  WakeRecord cancel(WakeRecord record, {required DateTime at}) {
    if (record.status == WakeStatus.cancelled) return record;
    if (record.status == WakeStatus.confirmed) {
      throw StateError('확정된 기상 기록은 후보 취소 대상이 아닙니다.');
    }
    return WakeRecord(
      id: record.id,
      observedAt: record.observedAt,
      source: record.source,
      status: WakeStatus.cancelled,
      decidedAt: at,
    );
  }

  WakeRecord recordManual({
    required String id,
    required DateTime wakeAt,
    required DateTime recordedAt,
  }) {
    if (wakeAt.isAfter(recordedAt)) {
      throw ArgumentError('미래 시각을 기상 기록으로 입력할 수 없습니다.');
    }
    return WakeRecord(
      id: id,
      observedAt: recordedAt,
      source: WakeSource.manual,
      status: WakeStatus.confirmed,
      decidedAt: recordedAt,
      wakeAt: wakeAt,
    );
  }
}
