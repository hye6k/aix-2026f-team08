import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/ports.dart';
import 'package:morning_routine/domain/alarm_coordinator.dart';

class FakeAlarmPort implements AlarmPort {
  AlarmPermission allowed = AlarmPermission.granted;
  final events = <String>[];
  final reservations = <String, DateTime>{};
  bool failSchedule = false;
  @override
  Future<AlarmPermission> permission() async => allowed;
  @override
  Future<void> cancel(String id) async {
    events.add('cancel:$id');
    reservations.remove(id);
  }

  @override
  Future<void> schedule(AlarmRequest request) async {
    await Future<void>.delayed(Duration.zero);
    if (failSchedule) {
      throw StateError('예약 실패');
    }
    events.add('schedule:${request.id}');
    reservations[request.id] = request.at;
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 1, 7);
  AlarmRequest request(int minutes, {String id = 'wake'}) => AlarmRequest(
    id: id,
    at: now.add(Duration(minutes: minutes)),
  );

  test('중복 적용을 생략하고 설정 변경 시 이전 예약을 먼저 취소한다', () async {
    final port = FakeAlarmPort();
    final coordinator = AlarmCoordinator(port);
    expect(
      await coordinator.apply(request(10), now: now),
      AlarmApplyResult.scheduled,
    );
    expect(
      await coordinator.apply(request(10), now: now),
      AlarmApplyResult.unchanged,
    );
    await coordinator.apply(request(20, id: 'new'), now: now);
    expect(port.reservations, {'new': now.add(const Duration(minutes: 20))});
    expect(
      port.events.indexOf('cancel:wake'),
      lessThan(port.events.indexOf('schedule:new')),
    );
  });
  test('권한 철회는 기존 예약을 지우고 실패 상태를 명시한다', () async {
    final port = FakeAlarmPort();
    final coordinator = AlarmCoordinator(port);
    await coordinator.apply(request(10), now: now);
    port.allowed = AlarmPermission.denied;
    expect(
      await coordinator.apply(request(20), now: now),
      AlarmApplyResult.permissionDenied,
    );
    expect(port.reservations, isEmpty);
    expect(coordinator.scheduled, isNull);
  });
  test('동시 설정 변경을 순서대로 반영하고 마지막 예약 하나만 유지한다', () async {
    final port = FakeAlarmPort();
    final coordinator = AlarmCoordinator(port);
    await Future.wait([
      coordinator.apply(request(10), now: now),
      coordinator.apply(request(20), now: now),
      coordinator.apply(request(30), now: now),
    ]);
    expect(port.reservations, {'wake': now.add(const Duration(minutes: 30))});
    expect(coordinator.scheduled!.at, now.add(const Duration(minutes: 30)));
  });
  test('다시 울림과 기상 확인 취소는 별도 조작이며 과거 예약은 거부한다', () async {
    final port = FakeAlarmPort();
    final coordinator = AlarmCoordinator(port);
    await coordinator.snooze(id: 'wake', now: now);
    expect(port.reservations['wake'], now.add(const Duration(minutes: 5)));
    await coordinator.wakeConfirmed('wake');
    expect(port.reservations, isEmpty);
    await expectLater(
      coordinator.apply(request(0), now: now),
      throwsArgumentError,
    );
  });
  test('예약 오류를 호출자에게 반환하고 이후 요청은 계속 처리한다', () async {
    final port = FakeAlarmPort()..failSchedule = true;
    final coordinator = AlarmCoordinator(port);
    await expectLater(
      coordinator.apply(request(10), now: now),
      throwsStateError,
    );
    expect(coordinator.scheduled, isNull);
    port.failSchedule = false;
    await coordinator.apply(request(20), now: now);
    expect(port.reservations['wake'], now.add(const Duration(minutes: 20)));
  });
}
