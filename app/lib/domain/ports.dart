import 'models.dart';

/// 소비자가 현재 앱 상태에서 수행할 수 없는 편집 작업을 설명한다.
class StoreActionBlocked implements Exception {
  const StoreActionBlocked(this.message);
  final String message;
}

/// 저장소를 연 앱 조립 계층이 수명을 소유하고 화면·서비스에는 주입한다.
/// 주입받은 소비자는 빌린 저장소를 닫지 않는다.
abstract interface class RoutineStore {
  Future<AppSettings?> loadSettings();
  Future<void> saveSettings(AppSettings settings);
  Future<List<Routine>> listRoutines();
  Future<void> saveRoutine(Routine routine);
  Future<void> deleteRoutine(String id);
  Future<List<WakeRecord>> listWakeRecords();
  Future<void> saveWakeRecord(WakeRecord record);
  Future<List<RoutineRun>> listRuns();
  Future<void> saveRun(RoutineRun run);

  /// 수명 소유자만 호출한다. 모든 소비자의 작업·구독 정리 후 닫는다.
  /// close 후 재사용하거나 다른 wrapper가 독립 연결이라고 가정하지 않는다.
  Future<void> close();
}

class AlarmRequest {
  AlarmRequest({required this.id, required this.at}) {
    requireText(id, 'id');
  }
  final String id;
  final DateTime at;
}

enum AlarmPermission { granted, denied }

abstract interface class AlarmPort {
  Future<AlarmPermission> permission();
  Future<void> schedule(AlarmRequest request);
  Future<void> cancel(String id);
}

class ActivitySignal {
  const ActivitySignal({required this.at, required this.source});
  final DateTime at;
  final WakeSource source;
}

abstract interface class ActivitySignalPort {
  Stream<ActivitySignal> get signals;
}
