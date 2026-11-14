import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../application/morning_session.dart';
import '../domain/models.dart';
import '../application/session_port.dart';
import '../data/sqlite_store.dart';
import '../platform/android_morning_platform.dart';

/// 앱 수명 동안 DB와 플랫폼 구독을 소유한다. 화면은 session을 호출한다.
class MorningRuntime with WidgetsBindingObserver {
  MorningRuntime._(this.store, this.platform, this.session);
  final SessionStore store;
  final AndroidMorningPlatform platform;
  final MorningSession session;
  final platformError = ValueNotifier<Object?>(null);
  final permissions = ValueNotifier<AndroidPermissionState?>(null);
  StreamSubscription<AndroidMorningEvent>? _subscription;
  StreamSubscription<SessionView>? _sessionSubscription;
  Future<void> _promptTail = Future<void>.value();
  String? _promptKey;
  Future<void> _nativeTail = Future<void>.value();
  Future<void> _refreshTail = Future<void>.value();
  final _handled = <String>{};
  Timer? _timer;
  bool _closed = false;

  static Future<MorningRuntime> open({
    Future<SessionStore> Function()? openStore,
    AndroidMorningPlatform? platform,
    DateTime Function()? clock,
    String Function()? newId,
  }) async {
    final native = platform ?? AndroidMorningPlatform();
    final store = await (openStore?.call() ?? SqliteRoutineStore.openDefault());
    final random = Random.secure();
    final session = MorningSession(
      store: store,
      alarmPort: native,
      signals: native,
      clock: clock ?? DateTime.now,
      newId:
          newId ??
          () => List.generate(
            16,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join(),
    );
    final runtime = MorningRuntime._(store, native, session);
    try {
      try {
        await session.initialize();
      } catch (e) {
        if (!session.view.cancellationPending) rethrow;
        runtime.platformError.value = e;
      }
      runtime._subscription = native.events.listen(
        runtime._receive,
        onError: (Object e) {
          runtime.platformError.value = e;
        },
      );
      runtime._sessionSubscription = session.changes.listen((_) {
        runtime._syncWakePrompt().catchError((Object e) {
          if (!runtime._closed) runtime.platformError.value = e;
        });
      });
      // 플랫폼 실패가 저장된 루틴까지 접근 불가로 만들지 않게 별도로 노출한다.
      try {
        await runtime.refreshPlatform();
      } catch (e) {
        runtime.platformError.value = e;
      }
      WidgetsBinding.instance.addObserver(runtime);
      runtime._startTimer();
      return runtime;
    } catch (_) {
      await runtime._subscription?.cancel();
      await runtime._sessionSubscription?.cancel();
      await runtime._promptTail;
      await session.close();
      await store.close();
      rethrow;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => session.refreshClock(),
    );
  }

  void _receive(AndroidMorningEvent event) {
    _enqueue(event).catchError((Object e) {
      if (!_closed) platformError.value = e;
    });
  }

  Future<void> _enqueue(AndroidMorningEvent event) {
    final result = _nativeTail.then((_) async {
      if (!event.persisted) return;
      if (event.kind == AndroidEventKind.alarmError) {
        platformError.value = StateError(event.error ?? 'Android 알람 오류');
        if (!_handled.contains(event.id)) {
          await session.nativeAlarmChanged();
          _handled.add(event.id);
        }
        // 오류는 네이티브 확인창에서 사용자가 확인할 때까지 보존한다.
        return;
      }
      if (_handled.contains(event.id)) return;
      await session.nativeAlarmChanged();
      await platform.acknowledgeAlarmEvent(event.id);
      _handled.add(event.id);
    });
    _nativeTail = result.then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {},
    );
    return result;
  }

  Future<void> _syncWakePrompt({bool force = false}) {
    final result = _promptTail.then((_) async {
      if (_closed) return;
      final wake = session.view.wake;
      final pending = wake?.status == WakeStatus.pending;
      final key = pending ? wake!.id : 'clear';
      if (!force && _promptKey == key) return;
      if (pending) {
        await platform.showWakeCandidate(wake!);
      } else {
        await platform.clearWakeCandidate();
      }
      _promptKey = key;
    });
    _promptTail = result.then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {},
    );
    return result;
  }

  Future<void> refreshPlatform() {
    if (_closed) return Future<void>.value();
    final result = _refreshTail.then((_) => _refreshPlatform());
    _refreshTail = result.then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {},
    );
    return result;
  }

  Future<void> _refreshPlatform() async {
    if (_closed) return;
    platformError.value = null;
    permissions.value = await platform.permissions();
    for (final event in await platform.pendingAlarmEvents()) {
      await _enqueue(event);
    }
    if (session.view.cancellationPending) await session.retryAlarm();
    await _syncWakePrompt(force: true);
    session.refreshClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed) return;
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      refreshPlatform().catchError((Object e) {
        if (!_closed) platformError.value = e;
      });
    } else {
      _timer?.cancel();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    await _subscription?.cancel();
    await _sessionSubscription?.cancel();
    await _refreshTail;
    await _promptTail;
    await _nativeTail;
    await session.close();
    // 마지막 변경 직후 화면이 닫혀 스트림 전달이 취소되어도 저장된 최종 상태를 반영한다.
    try {
      final wake = session.view.wake;
      if (wake?.status == WakeStatus.pending) {
        await platform.showWakeCandidate(wake!);
      } else {
        await platform.clearWakeCandidate();
      }
    } catch (e) {
      // OS 요청 실패는 저장을 되돌리지 않는다. 다음 기동에서 다시 동기화한다.
      platformError.value = e;
    }
    await store.close();
    platformError.dispose();
    permissions.dispose();
  }
}

class MorningScope extends InheritedWidget {
  const MorningScope({required this.runtime, required super.child, super.key});
  final MorningRuntime runtime;
  static MorningRuntime of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MorningScope>()!.runtime;
  @override
  bool updateShouldNotify(MorningScope oldWidget) =>
      runtime != oldWidget.runtime;
}
