import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/models.dart';
import '../domain/ports.dart';

class AndroidPermissionState {
  const AndroidPermissionState({
    required this.exactAlarm,
    required this.notifications,
  });
  final bool exactAlarm;
  final bool notifications;
  bool get canSchedule => exactAlarm && notifications;
}

enum AndroidEventKind {
  screenOn,
  alarmFired,
  alarmDismissed,
  alarmSnoozed,
  alarmError,
}

class AndroidMorningEvent {
  AndroidMorningEvent.fromMessage(Object? message) {
    final data = Map<Object?, Object?>.from(message as Map);
    id = data['eventId']! as String;
    kind = AndroidEventKind.values.byName(data['kind']! as String);
    at = DateTime.fromMillisecondsSinceEpoch(
      (data['atMillis']! as num).toInt(),
    );
    alarmId = data['alarmId'] as String?;
    final next = data['scheduledAtMillis'] as num?;
    scheduledAt = next == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(next.toInt());
    error = data['error'] as String?;
    requireText(id, 'eventId');
    if (kind != AndroidEventKind.screenOn) {
      requireText(alarmId ?? '', 'alarmId');
    }
  }
  late final String id;
  late final AndroidEventKind kind;
  late final DateTime at;
  late final String? alarmId;
  late final DateTime? scheduledAt;
  late final String? error;
  bool get persisted => kind != AndroidEventKind.screenOn;
}

/// Android API 호출과 순수 도메인 계약의 경계. 권한 요청은 명시적 UI 조작에서 호출한다.
class AndroidMorningPlatform implements AlarmPort, ActivitySignalPort {
  AndroidMorningPlatform({MethodChannel? methods, Stream<Object?>? events})
    : _methods = methods ?? const MethodChannel('morning_routine/platform'),
      _messages =
          events ??
          const EventChannel('morning_routine/platform_events')
              .receiveBroadcastStream();
  final MethodChannel _methods;
  final Stream<Object?> _messages;
  late final Stream<AndroidMorningEvent> events = _messages
      .map(AndroidMorningEvent.fromMessage)
      .asBroadcastStream(onCancel: (subscription) => subscription.cancel());

  Future<AndroidPermissionState> permissions() async {
    final values = await _methods.invokeMapMethod<String, Object?>(
      'getPermissions',
    );
    if (values == null ||
        values['exactAlarm'] is! bool ||
        values['notifications'] is! bool) {
      throw const FormatException('Android 권한 응답이 올바르지 않습니다.');
    }
    return AndroidPermissionState(
      exactAlarm: values['exactAlarm']! as bool,
      notifications: values['notifications']! as bool,
    );
  }

  @override
  Future<AlarmPermission> permission() async =>
      (await permissions()).canSchedule
      ? AlarmPermission.granted
      : AlarmPermission.denied;
  Future<void> requestExactAlarmPermission() =>
      _methods.invokeMethod<void>('requestExactAlarmPermission');
  Future<void> requestNotificationPermission() =>
      _methods.invokeMethod<void>('requestNotificationPermission');
  @override
  Future<void> schedule(AlarmRequest request) => _methods.invokeMethod<void>(
    'schedule',
    {'id': request.id, 'atMillis': request.at.millisecondsSinceEpoch},
  );
  @override
  Future<void> cancel(String id) {
    requireText(id, 'id');
    return _methods.invokeMethod<void>('cancel', {'id': id});
  }

  Future<List<AndroidMorningEvent>> pendingAlarmEvents() async {
    final messages = await _methods.invokeListMethod<Object?>(
      'pendingAlarmEvents',
    );
    return (messages ?? [])
        .map(AndroidMorningEvent.fromMessage)
        .toList(growable: false);
  }

  Future<void> acknowledgeAlarmEvent(String id) {
    requireText(id, 'eventId');
    return _methods.invokeMethod<void>('acknowledgeAlarmEvent', {
      'eventId': id,
    });
  }

  @override
  Stream<ActivitySignal> get signals => events
      .where((event) => event.kind == AndroidEventKind.screenOn)
      .map(
        (event) => ActivitySignal(at: event.at, source: WakeSource.screenOn),
      );
}
