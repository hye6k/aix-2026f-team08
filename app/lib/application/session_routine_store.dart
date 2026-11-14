import '../domain/models.dart';
import '../domain/ports.dart';
import 'morning_session.dart';
import 'session_port.dart';

/// 기존 편집 화면이 앱 소유 저장소를 빌려 사용하도록 연결한다.
/// 활성 계획의 변경은 세션 트랜잭션과 알람 적용 경계를 거친다.
class SessionRoutineStore implements RoutineStore {
  SessionRoutineStore(this.session, {this.onAlarmPending});
  final MorningSession session;
  final void Function()? onAlarmPending;
  SessionStore get _store => session.store;

  @override
  Future<AppSettings?> loadSettings() => _store.loadSettings();
  @override
  Future<List<Routine>> listRoutines() => _store.listRoutines();
  @override
  Future<List<WakeRecord>> listWakeRecords() => _store.listWakeRecords();
  @override
  Future<List<RoutineRun>> listRuns() => _store.listRuns();
  @override
  Future<void> saveWakeRecord(WakeRecord record) =>
      _store.saveWakeRecord(record);
  @override
  Future<void> saveRun(RoutineRun run) => _store.saveRun(run);

  void _ensureNotRunning() {
    if (session.view.run?.status == RunStatus.running) {
      throw const StoreActionBlocked('진행 중인 루틴을 완료하거나 중단한 뒤 계획을 변경해 주세요.');
    }
  }

  Future<void> _configure({
    required AppSettings settings,
    required Routine routine,
    required DateTime arrivalDay,
    required bool Function() saved,
  }) async {
    _ensureNotRunning();
    try {
      await session.configure(
        settings: settings,
        routine: routine,
        arrivalDay: arrivalDay,
      );
    } catch (_) {
      // 계획은 DB에 먼저 저장되므로 OS 적용 실패를 저장 실패로 표시하지 않는다.
      if (!saved() || !session.view.alarmUpdatePending) rethrow;
    }
    if (session.view.alarmUpdatePending || session.view.cancellationPending) {
      onAlarmPending?.call();
    }
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final checkpoint = await _store.loadSession();
    if (checkpoint == null) return _store.saveSettings(settings);
    final matches = (await _store.listRoutines()).where(
      (r) => r.id == checkpoint.routineId,
    );
    if (matches.length != 1) throw StateError('선택한 루틴을 찾을 수 없습니다.');
    await _configure(
      settings: settings,
      routine: matches.single,
      arrivalDay: checkpoint.arrivalDay,
      saved: () => identical(session.view.settings, settings),
    );
  }

  @override
  Future<void> saveRoutine(Routine routine) async {
    final checkpoint = await _store.loadSession();
    if (checkpoint == null || checkpoint.routineId != routine.id) {
      return _store.saveRoutine(routine);
    }
    final settings = await _store.loadSettings();
    if (settings == null) throw StateError('계획 설정을 찾을 수 없습니다.');
    await _configure(
      settings: settings,
      routine: routine,
      arrivalDay: checkpoint.arrivalDay,
      saved: () => session.view.routines.any((r) => identical(r, routine)),
    );
  }

  @override
  Future<void> deleteRoutine(String id) async {
    final checkpoint = await _store.loadSession();
    if (checkpoint?.routineId == id) {
      throw const StoreActionBlocked(
        '현재 계획에 사용하는 루틴이에요. 다른 루틴을 계획에 선택한 뒤 삭제해 주세요.',
      );
    }
    return _store.deleteRoutine(id);
  }

  @override
  Future<void> close() async =>
      throw UnsupportedError('앱이 소유한 저장소는 화면에서 닫을 수 없습니다.');
}
