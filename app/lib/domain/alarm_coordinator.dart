import 'models.dart';
import 'ports.dart';

enum AlarmApplyResult { scheduled, unchanged, permissionDenied }

/// 요청 실패와 이전 예약 복구 결과를 함께 반환한다. 복원 성공도 변경 성공은 아니다.
class AlarmApplyFailure extends StateError {
  AlarmApplyFailure({
    required this.request,
    required this.previous,
    required this.cause,
    required this.previousRestored,
    this.recoveryError,
  }) : super(
         previousRestored
             ? '알람 변경에 실패하여 이전 예약을 복원했습니다.'
             : '알람 변경에 실패했고 이전 예약을 보장할 수 없습니다. 재예약을 확인하세요.',
       );
  final AlarmRequest request;
  final AlarmRequest? previous;
  final Object cause;
  final bool previousRestored;
  final Object? recoveryError;
}

class AlarmCoordinator {
  AlarmCoordinator(this.port, {this.clock});
  final AlarmPort port;
  final DateTime Function()? clock;
  AlarmRequest? _scheduled;
  AlarmApplyFailure? _lastFailure;
  Future<void> _tail = Future<void>.value();
  AlarmRequest? get scheduled => _scheduled;
  AlarmApplyFailure? get lastFailure => _lastFailure;

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<AlarmApplyResult> apply(
    AlarmRequest request, {
    required DateTime now,
  }) => _serial(() async {
    if (!request.at.isAfter(now)) throw ArgumentError('알람은 미래 시각이어야 합니다.');
    if (await port.permission() != AlarmPermission.granted) {
      await _cancelCurrent();
      await port.cancel(request.id);
      _lastFailure = null;
      return AlarmApplyResult.permissionDenied;
    }
    if (_scheduled?.id == request.id &&
        _scheduled!.at.isAtSameMomentAs(request.at)) {
      _lastFailure = null;
      return AlarmApplyResult.unchanged;
    }
    final previous = _scheduled;
    try {
      await _cancelCurrent();
      await port.cancel(request.id);
      await port.schedule(request);
      _scheduled = request;
      _lastFailure = null;
      return AlarmApplyResult.scheduled;
    } catch (cause) {
      _scheduled = null;
      Object? recoveryError;
      var restored = false;
      try {
        // 새 예약이 실제 반영된 뒤 응답만 실패했을 수 있으므로 먼저 정리한다.
        await port.cancel(request.id);
        if (previous != null && previous.at.isAfter(clock?.call() ?? now)) {
          if (await port.permission() != AlarmPermission.granted) {
            throw StateError('복구 시 알람 권한이 없습니다.');
          }
          await port.cancel(previous.id);
          await port.schedule(previous);
          _scheduled = previous;
          restored = true;
        }
      } catch (error) {
        recoveryError = error;
      }
      final failure = AlarmApplyFailure(
        request: request,
        previous: previous,
        cause: cause,
        previousRestored: restored,
        recoveryError: recoveryError,
      );
      _lastFailure = failure;
      throw failure;
    }
  });

  Future<void> _cancelCurrent() async {
    final previous = _scheduled;
    if (previous != null) {
      await port.cancel(previous.id);
      _scheduled = null;
    }
  }

  Future<void> cancel(String id) => _serial(() async {
    await port.cancel(id);
    if (_scheduled?.id == id) _scheduled = null;
    _lastFailure = null;
  });

  /// 네이티브 버튼 조작 후 OS 호출 없이 캐시만 버린다.
  Future<void> invalidate() => _serial(() async {
    _scheduled = null;
  });

  Future<AlarmApplyResult> snooze({
    required String id,
    required DateTime now,
    Duration interval = const Duration(minutes: 5),
  }) {
    requireDuration(interval, 'interval');
    return apply(
      AlarmRequest(id: id, at: now.add(interval)),
      now: now,
    );
  }

  // 다음 날 자동 예약은 하지 않는다. 새 날짜의 계획은 호출자가 명시한다.
  Future<void> wakeConfirmed(String alarmId) => cancel(alarmId);
}
