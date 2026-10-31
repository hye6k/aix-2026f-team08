import 'models.dart';

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
