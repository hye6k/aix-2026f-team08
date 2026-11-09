import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/ports.dart';
import 'package:morning_routine/domain/alarm_coordinator.dart';

class FakeAlarmPort implements AlarmPort {
  AlarmPermission allowed = AlarmPermission.granted;
  final events = <String>[];
  final reservations = <String, DateTime>{};
  bool failSchedule = false;
  final failAt = <DateTime>{};
  bool failAfterWrite = false;
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
    if (failSchedule || failAt.contains(request.at)) {
      throw StateError('예약 실패');
    }
    events.add('schedule:${request.id}');
    reservations[request.id] = request.at;
    if (failAfterWrite && request.at.minute == 20) throw StateError('응답 전 실패');
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 1, 7);
  AlarmRequest request(int minutes, {String id = 'wake'}) => AlarmRequest(
    id: id,
    at: now.add(Duration(minutes: minutes)),
  );

  test('중복 적용을 생략하고 새 예약 성공 후 이전 ID를 취소한다', () async {
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
      greaterThan(port.events.indexOf('schedule:new')),
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
  test('같은 ID 변경 실패는 이전 미래 예약을 복원한다', () async {
    final port = FakeAlarmPort();
    final coordinator = AlarmCoordinator(port);
    await coordinator.apply(request(10), now: now);
    port.failAt.add(request(20).at);
    await expectLater(
      coordinator.apply(request(20), now: now),
      throwsStateError,
    );
    expect(port.reservations, {'wake': request(10).at});
    expect(coordinator.scheduled!.at, request(10).at);
  });
  test('다른 ID 변경 실패는 시도한 예약을 정리하고 이전 ID를 복원한다', () async {
    final port = FakeAlarmPort();
    final coordinator = AlarmCoordinator(port);
    await coordinator.apply(request(10), now: now);
    port.failAfterWrite = true;
    await expectLater(
      coordinator.apply(request(20, id: 'new'), now: now),
      throwsStateError,
    );
    expect(port.reservations, {'wake': request(10).at});
  });
  test('복원도 실패하면 예약 없음과 두 실패 원인을 반환한다', () async {
    final port = FakeAlarmPort();
    final c = AlarmCoordinator(port);
    await c.apply(request(10), now: now);
    port.failSchedule = true;
    await expectLater(
      c.apply(request(20), now: now),
      throwsA(
        isA<AlarmApplyFailure>()
            .having((f) => f.previousRestored, '복원', false)
            .having((f) => f.recoveryError, '복원 오류', isNotNull),
      ),
    );
    expect(c.scheduled, isNull);
    expect(port.reservations, {'wake': request(10).at});
    expect(c.lastFailure, isNotNull);
    port.failSchedule = false;
    await c.apply(request(30), now: now);
    expect(c.lastFailure, isNull);
  });
  test('복구 도중 지난 이전 알람을 다시 예약하지 않는다', () async {
    final port = FakeAlarmPort();
    var current = now;
    final c = AlarmCoordinator(port, clock: () => current);
    await c.apply(request(10), now: now);
    current = now.add(const Duration(minutes: 15));
    port.failAt.add(request(20).at);
    await expectLater(
      c.apply(request(20), now: current),
      throwsA(
        isA<AlarmApplyFailure>().having((f) => f.previousRestored, '복원', false),
      ),
    );
    expect(port.events.where((e) => e == 'schedule:wake').length, 1);
    expect(c.scheduled, isNull);
  });
  test('다시 울림 실패도 이전 예약으로 복원하고 캐시 무효화는 OS를 변경하지 않는다', () async {
    final port = FakeAlarmPort();
    final c = AlarmCoordinator(port);
    await c.apply(request(10), now: now);
    port.failAt.add(request(5).at);
    await expectLater(
      c.snooze(id: 'wake', now: now),
      throwsA(
        isA<AlarmApplyFailure>().having((f) => f.previousRestored, '복원', true),
      ),
    );
    final events = port.events.length;
    await c.invalidate();
    expect(c.scheduled, isNull);
    expect(port.events.length, events);
    expect(port.reservations['wake'], request(10).at);
  });
  test('재시작 후 캐시가 없어도 예약 실패 전에 기존 OS 예약을 지우지 않는다', () async {
    final port = FakeAlarmPort();
    port.reservations['wake'] = request(10).at;
    final c = AlarmCoordinator(port);
    port.failAt.add(request(20).at);
    await expectLater(
      c.apply(request(20), now: now),
      throwsA(isA<AlarmApplyFailure>()),
    );
    expect(port.reservations, {'wake': request(10).at});
    expect(port.events.where((e) => e == 'cancel:wake'), isEmpty);
  });
}
