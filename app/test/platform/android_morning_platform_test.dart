import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/ports.dart';
import 'package:morning_routine/platform/android_morning_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('morning_routine/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late StreamController<Object?> messages;
  late AndroidMorningPlatform platform;
  setUp(() {
    calls = [];
    messages = StreamController<Object?>.broadcast();
    platform = AndroidMorningPlatform(
      methods: channel,
      events: messages.stream,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getPermissions') {
        return {'exactAlarm': true, 'notifications': true};
      }
      if (call.method == 'pendingAlarmEvents') return <Object?>[];
      return null;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await messages.close();
  });
  test('실제 예약의 ID·epoch 밀리초와 취소를 채널에 전달한다', () async {
    final at = DateTime.utc(2026, 11, 8, 7);
    await platform.schedule(AlarmRequest(id: 'wake', at: at));
    await platform.cancel('wake');
    expect(calls[0].method, 'schedule');
    expect(calls[0].arguments, {
      'id': 'wake',
      'atMillis': at.millisecondsSinceEpoch,
    });
    expect(calls[1].arguments, {'id': 'wake'});
  });
  test('알림·정확한 알람 중 하나라도 거부되면 예약 권한 거부다', () async {
    for (final exact in [false, true]) {
      for (final notification in [false, true]) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {'exactAlarm': exact, 'notifications': notification},
        );
        expect(
          await platform.permission(),
          exact && notification
              ? AlarmPermission.granted
              : AlarmPermission.denied,
        );
      }
    }
  });
  test('사용자 요청에서만 권한 설정을 열고 승인으로 간주하지 않는다', () async {
    await platform.requestExactAlarmPermission();
    await platform.requestNotificationPermission();
    expect(calls.map((c) => c.method), [
      'requestExactAlarmPermission',
      'requestNotificationPermission',
    ]);
  });
  test('플랫폼 권한·예약 오류를 성공으로 바꾸지 않는다', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'permission_denied'),
    );
    expect(
      platform.schedule(AlarmRequest(id: 'wake', at: DateTime.now())),
      throwsA(isA<PlatformException>()),
    );
  });
  test('잘못된 권한 응답을 거부한다', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'exactAlarm': 'yes'},
    );
    expect(platform.permissions(), throwsFormatException);
  });
  test('화면 이벤트만 실제 화면 출처로 전달하고 알람은 기상으로 만들지 않는다', () async {
    final signals = <ActivitySignal>[];
    final alarms = <AndroidMorningEvent>[];
    final one = platform.signals.listen(signals.add);
    final two = platform.events
        .where((e) => e.kind != AndroidEventKind.screenOn)
        .listen(alarms.add);
    messages.add({'eventId': 's', 'kind': 'screenOn', 'atMillis': 1000});
    for (final kind in ['alarmFired', 'alarmDismissed', 'alarmSnoozed']) {
      messages.add({
        'eventId': kind,
        'kind': kind,
        'atMillis': 2000,
        'alarmId': 'wake',
      });
    }
    await Future<void>.delayed(Duration.zero);
    expect(signals, hasLength(1));
    expect(signals.single.source, WakeSource.screenOn);
    expect(alarms, hasLength(3));
    expect(alarms.every((e) => e.persisted), isTrue);
    await one.cancel();
    await two.cancel();
  });
  test('재실행 전 알람 동작을 읽고 명시적으로 확인 처리한다', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pendingAlarmEvents') {
        return [
          {
            'eventId': 'event',
            'kind': 'alarmSnoozed',
            'alarmId': 'wake',
            'atMillis': 1000,
            'scheduledAtMillis': 301000,
          },
        ];
      }
      return null;
    });
    final pending = await platform.pendingAlarmEvents();
    expect(pending.single.scheduledAt!.millisecondsSinceEpoch, 301000);
    await platform.acknowledgeAlarmEvent(pending.single.id);
    expect(calls.last.arguments, {'eventId': 'event'});
  });
  test('미확인 후보 확인 요청과 해제를 알람 예약과 분리한다', () async {
    final at = DateTime.utc(2026, 11, 7, 7);
    await platform.showWakeCandidate(
      WakeRecord(
        id: 'candidate',
        observedAt: at,
        source: WakeSource.screenOn,
        status: WakeStatus.pending,
      ),
    );
    await platform.clearWakeCandidate();
    expect(calls.map((c) => c.method), [
      'showWakeCandidate',
      'clearWakeCandidate',
    ]);
    expect(calls.first.arguments, {
      'id': 'candidate',
      'atMillis': at.millisecondsSinceEpoch,
    });
  });
  test('확정 기상을 후보 확인 요청으로 표시하지 않는다', () {
    final at = DateTime.utc(2026, 11, 7, 7);
    expect(
      () => platform.showWakeCandidate(
        WakeRecord(
          id: 'w',
          observedAt: at,
          source: WakeSource.manual,
          status: WakeStatus.confirmed,
          decidedAt: at,
          wakeAt: at,
        ),
      ),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });
  test('알람 이벤트에 알람 ID가 없으면 오류로 노출한다', () {
    expect(
      () => AndroidMorningEvent.fromMessage({
        'eventId': 'e',
        'kind': 'alarmFired',
        'atMillis': 0,
      }),
      throwsArgumentError,
    );
  });
}
