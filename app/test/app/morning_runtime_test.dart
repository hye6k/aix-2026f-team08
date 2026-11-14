import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/bootstrap.dart';
import 'package:morning_routine/app/morning_runtime.dart';
import 'package:morning_routine/platform/android_morning_platform.dart';
import 'package:morning_routine/domain/ports.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/presentation/integrated_home.dart';
import 'package:morning_routine/presentation/settings_screen.dart';

import '../application/morning_session_test.dart'
    show MemoryStore, settings, routine;

class Native extends AndroidMorningPlatform {
  Native(this.input) : super(events: input.stream);
  final StreamController<Object?> input;
  final pending = <AndroidMorningEvent>[];
  final acknowledgements = <String>[];
  bool fail = false, failCancel = false, failPrompt = false;
  int prompts = 0, clearPrompts = 0;
  int schedules = 0, cancels = 0;
  Completer<AndroidPermissionState>? delayedPermissions;
  @override
  Future<AndroidPermissionState> permissions() async {
    if (fail) throw PlatformException(code: 'offline');
    return delayedPermissions?.future ??
        const AndroidPermissionState(exactAlarm: true, notifications: true);
  }

  @override
  Future<void> showWakeCandidate(WakeRecord candidate) async {
    if (failPrompt) throw PlatformException(code: 'prompt_denied');
    prompts++;
  }

  @override
  Future<void> clearWakeCandidate() async {
    clearPrompts++;
  }

  @override
  Future<void> schedule(AlarmRequest request) async {
    schedules++;
  }

  @override
  Future<void> cancel(String id) async {
    if (failCancel) throw StateError('cancel');
    cancels++;
  }

  @override
  Future<List<AndroidMorningEvent>> pendingAlarmEvents() async => [...pending];
  @override
  Future<void> acknowledgeAlarmEvent(String id) async {
    acknowledgements.add(id);
    pending.removeWhere((e) => e.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryStore db;
  late StreamController<Object?> events;
  late Native native;
  MorningRuntime? runtime;
  var now = DateTime.utc(2026, 11, 8, 7);
  Future<MorningRuntime> open() => MorningRuntime.open(
    openStore: () async => db,
    platform: native,
    clock: () => now,
    newId: () => 'candidate',
  );
  setUp(() {
    now = DateTime.utc(2026, 11, 8, 7);
    db = MemoryStore();
    events = StreamController<Object?>.broadcast();
    native = Native(events);
  });
  tearDown(() async {
    await runtime?.close();
    runtime = null;
    await events.close();
  });
  test('기동 조립 후 화면 신호가 저장된 후보로 연결된다', () async {
    runtime = await open();
    await runtime!.session.configure(
      settings: settings(),
      routine: routine(),
      arrivalDay: now,
    );
    events.add({
      'eventId': 'screen',
      'kind': 'screenOn',
      'atMillis': now.millisecondsSinceEpoch,
    });
    await Future<void>.delayed(Duration.zero);
    await runtime!.session.dismissAlarm();
    expect(runtime!.session.view.wake!.status, WakeStatus.pending);
  });
  test('기동 시 보존 알람은 확인 처리하지만 기상 확정·재예약하지 않는다', () async {
    final event = AndroidMorningEvent.fromMessage({
      'eventId': 'snooze',
      'kind': 'alarmSnoozed',
      'alarmId': 'morning-wake',
      'atMillis': now.millisecondsSinceEpoch,
    });
    native.pending.add(event);
    runtime = await open();
    expect(native.acknowledgements, ['snooze']);
    expect(native.schedules, 0);
    expect(runtime!.session.view.wake, isNull);
    events.add({
      'eventId': 'snooze',
      'kind': 'alarmSnoozed',
      'alarmId': 'morning-wake',
      'atMillis': now.millisecondsSinceEpoch,
    });
    await runtime!.refreshPlatform();
    expect(native.acknowledgements, ['snooze']);
  });
  test('플랫폼 오류가 나도 저장 데이터 접근 경계를 제공한다', () async {
    native.fail = true;
    runtime = await open();
    expect(runtime!.platformError.value, isA<PlatformException>());
    expect(runtime!.session.view.routines, isEmpty);
  });
  test('새로고침 중 종료해도 정리 이후 알림을 쓰지 않는다', () async {
    runtime = await open();
    native.delayedPermissions = Completer<AndroidPermissionState>();
    final refresh = runtime!.refreshPlatform();
    await Future<void>.delayed(Duration.zero);
    final close = runtime!.close();
    native.delayedPermissions!.complete(
      const AndroidPermissionState(exactAlarm: true, notifications: true),
    );
    await Future.wait([refresh, close]);
  });
  test('복원 중 알람 취소가 실패해도 확정 상태와 재시도 경로를 유지한다', () async {
    runtime = await open();
    await runtime!.session.configure(
      settings: settings(),
      routine: routine(),
      arrivalDay: now,
    );
    await runtime!.session.observe(
      ActivitySignal(at: now, source: WakeSource.screenOn),
    );
    native.failCancel = true;
    await expectLater(runtime!.session.confirmWake(), throwsStateError);
    await runtime!.close();
    runtime = null;
    native = Native(events)..failCancel = true;
    runtime = await open();
    expect(runtime!.session.view.wake!.status, WakeStatus.confirmed);
    expect(runtime!.session.view.cancellationPending, isTrue);
    expect(runtime!.platformError.value, isStateError);
    native.failCancel = false;
    await runtime!.refreshPlatform();
    expect(runtime!.session.view.cancellationPending, isFalse);
    expect(native.schedules, 0);
  });

  test('후보는 한 번 알리고 취소 후에는 확인 요청을 제거한다', () async {
    runtime = await open();
    await runtime!.session.configure(
      settings: settings(),
      routine: routine(),
      arrivalDay: now,
    );
    await runtime!.session.observe(
      ActivitySignal(at: now, source: WakeSource.screenOn),
    );
    await Future<void>.delayed(Duration.zero);
    expect(native.prompts, 1);
    await runtime!.session.observe(
      ActivitySignal(at: now, source: WakeSource.screenOn),
    );
    await Future<void>.delayed(Duration.zero);
    expect(native.prompts, 1);
    final before = native.clearPrompts;
    await runtime!.session.cancelCandidate();
    await Future<void>.delayed(Duration.zero);
    expect(native.clearPrompts, before + 1);
    expect(runtime!.session.view.wake!.status, WakeStatus.cancelled);
  });
  test('기상 확정 직후 종료해도 후보 알림을 최종 상태로 정리한다', () async {
    runtime = await open();
    await runtime!.session.configure(
      settings: settings(),
      routine: routine(),
      arrivalDay: now,
    );
    await runtime!.session.observe(
      ActivitySignal(at: now, source: WakeSource.screenOn),
    );
    await Future<void>.delayed(Duration.zero);
    final before = native.clearPrompts;
    await runtime!.session.confirmWake();
    await runtime!.close();
    expect(native.clearPrompts, greaterThan(before));
  });
  test('확인 요청 알림 실패는 후보를 잃지 않고 플랫폼 오류로 표시한다', () async {
    runtime = await open();
    await runtime!.session.configure(
      settings: settings(),
      routine: routine(),
      arrivalDay: now,
    );
    native.failPrompt = true;
    await runtime!.session.observe(
      ActivitySignal(at: now, source: WakeSource.screenOn),
    );
    await Future<void>.delayed(Duration.zero);
    expect(runtime!.session.view.wake!.status, WakeStatus.pending);
    expect(runtime!.platformError.value, isA<PlatformException>());
  });
  test('감지 종료 후 신호도 기존 pending 알림을 지우지 않는다', () async {
    runtime = await open();
    await runtime!.session.configure(
      settings: settings(),
      routine: routine(),
      arrivalDay: now,
    );
    await runtime!.session.observe(
      ActivitySignal(at: now, source: WakeSource.screenOn),
    );
    await Future<void>.delayed(Duration.zero);
    final id = runtime!.session.view.wake!.id;
    final clears = native.clearPrompts, prompts = native.prompts;
    now = DateTime.utc(2026, 11, 8, 9);
    events.add({
      'eventId': 'outside',
      'kind': 'screenOn',
      'atMillis': now.millisecondsSinceEpoch,
    });
    await Future<void>.delayed(Duration.zero);
    expect(runtime!.session.view.wake!.id, id);
    expect(native.clearPrompts, clears);
    expect(native.prompts, prompts);
  });
  test('이전 프로세스 권한 오류는 사용자 확인 전까지 보존한다', () async {
    native.pending.add(
      AndroidMorningEvent.fromMessage({
        'eventId': 'permission-error',
        'kind': 'alarmError',
        'alarmId': 'morning-wake',
        'atMillis': now.millisecondsSinceEpoch,
        'error': 'notification_permission_denied',
      }),
    );
    runtime = await open();
    expect(runtime!.platformError.value, isStateError);
    expect(native.acknowledgements, isEmpty);
    await runtime!.refreshPlatform();
    expect(runtime!.platformError.value, isStateError);
    expect(native.pending.single.id, 'permission-error');
    expect(runtime!.session.view.wake, isNull);
  });
  test('여러 오류가 사용자 확인 전 복귀와 재기동을 거쳐도 보존된다', () async {
    for (final id in ['first', 'second']) {
      native.pending.add(
        AndroidMorningEvent.fromMessage({
          'eventId': id,
          'kind': 'alarmError',
          'alarmId': 'morning-wake',
          'atMillis': now.millisecondsSinceEpoch,
          'error': 'schedule_failed',
        }),
      );
    }
    runtime = await open();
    await runtime!.refreshPlatform();
    expect(native.pending.map((e) => e.id), ['first', 'second']);
    await runtime!.close();
    runtime = await open();
    expect(native.pending.map((e) => e.id), ['first', 'second']);
    await native.acknowledgeAlarmEvent('first'); // 사용자 확인을 모의한다.
    await runtime!.refreshPlatform();
    expect(native.pending.map((e) => e.id), ['second']);
    expect(runtime!.platformError.value, isStateError);
  });
  test('네이티브 다시 울림 이벤트는 재예약 없이 캐시를 무효화한다', () async {
    runtime = await open();
    await runtime!.session.configure(
      settings: settings(),
      routine: routine(),
      arrivalDay: now,
    );
    final schedules = native.schedules, cancels = native.cancels;
    events.add({
      'eventId': 'snoozed-native',
      'kind': 'alarmSnoozed',
      'alarmId': 'morning-wake',
      'atMillis': now.millisecondsSinceEpoch,
      'scheduledAtMillis': now
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
    });
    await Future<void>.delayed(Duration.zero);
    await runtime!.refreshPlatform();
    expect(native.schedules, schedules);
    expect(native.cancels, cancels);
    expect(runtime!.session.view.wake, isNull);
    await runtime!.session.retryAlarm();
    expect(native.schedules, schedules + 1);
  });
  testWidgets('초기화 재시도 버튼의 중복 입력은 한 번만 연다', (tester) async {
    var calls = 0;
    final result = Completer<MorningRuntime>();
    await tester.pumpWidget(
      MorningBootstrap(
        openRuntime: () {
          calls++;
          if (calls == 1) return Future.error(StateError('first'));
          return result.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    button.onPressed!();
    button.onPressed!();
    expect(calls, 2);
    result.completeError(StateError('retry'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('기동한 앱의 기존 설정 화면은 런타임 소유 저장소를 공유한다', (tester) async {
    runtime = await open();
    await tester.pumpWidget(
      MorningBootstrap(openRuntime: () async => runtime!),
    );
    await tester.pumpAndSettle();
    final bridge = tester
        .widget<IntegratedHomeScreen>(find.byType(IntegratedHomeScreen))
        .store;
    expect(bridge.session.store, same(db));
    await tester.tap(find.text('시간 설정'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SettingsScreen>(find.byType(SettingsScreen)).store,
      same(bridge),
    );
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    expect(await runtime!.store.loadSettings(), isNull);
    bridge.onAlarmPending!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('알람 적용이 대기 중'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('기동 실패 화면은 재시도하며 원본 오류를 노출하지 않는다', (tester) async {
    var tries = 0;
    await tester.pumpWidget(
      MorningBootstrap(
        openRuntime: () async {
          tries++;
          throw StateError('private database path');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('저장된 정보를 불러오지 못했어요.'), findsOneWidget);
    expect(find.textContaining('private database'), findsNothing);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(tries, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
