import 'models.dart';
import 'ports.dart';

enum AlarmApplyResult { scheduled, unchanged, permissionDenied }

class AlarmCoordinator {
  AlarmCoordinator(this.port);
  final AlarmPort port;
  AlarmRequest? _scheduled;
  Future<void> _tail = Future<void>.value();
  AlarmRequest? get scheduled => _scheduled;

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
    if (!request.at.isAfter(now)) {
      throw ArgumentError('알람은 미래 시각이어야 합니다.');
    }
    if (await port.permission() != AlarmPermission.granted) {
      await _cancelCurrent();
      // 프로세스 재시작 전 동일 ID로 예약된 알람도 취소한다.
      await port.cancel(request.id);
      return AlarmApplyResult.permissionDenied;
    }
    if (_scheduled?.id == request.id &&
        _scheduled!.at.isAtSameMomentAs(request.at)) {
      return AlarmApplyResult.unchanged;
    }
    await _cancelCurrent();
    await port.cancel(request.id);
    await port.schedule(request);
    _scheduled = request;
    return AlarmApplyResult.scheduled;
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
    if (_scheduled?.id == id) {
      _scheduled = null;
    }
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

  // 알람 해제와 기상 확정 이벤트는 호출자가 구분한다. 이 클래스는 기상 기록을 수정하지 않는다.
  Future<void> wakeConfirmed(String alarmId) => cancel(alarmId);
}
