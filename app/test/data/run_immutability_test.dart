import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:morning_routine/data/sqlite_store.dart';
import 'package:morning_routine/domain/models.dart';

void main() {
  sqfliteFfiInit();
  late SqliteRoutineStore store;
  final at = DateTime.utc(2026, 11, 7, 7);
  RoutineRun snapshot({
    int revision = 1,
    String name = '아침',
    int duration = 10,
    int startShift = 0,
    int updateMinute = 5,
    bool reversed = false,
  }) {
    final start = at.add(Duration(minutes: startShift));
    final first = RoutineStep(
      id: 'a',
      name: '세면',
      expected: Duration(minutes: duration),
    );
    final second = RoutineStep(
      id: 'b',
      name: '식사',
      expected: const Duration(minutes: 10),
    );
    return RoutineRun(
      id: 'run',
      routineId: 'r',
      routineName: name,
      startedAt: start,
      updatedAt: start.add(Duration(minutes: updateMinute)),
      revision: revision,
      status: RunStatus.running,
      steps: [
        StepExecution(
          step: first,
          status: reversed ? StepStatus.active : StepStatus.completed,
          startedAt: start,
          endedAt: reversed ? null : start.add(const Duration(minutes: 2)),
        ),
        StepExecution(
          step: second,
          status: reversed ? StepStatus.pending : StepStatus.active,
          startedAt: reversed ? null : start.add(const Duration(minutes: 2)),
        ),
      ],
    );
  }

  setUp(() async {
    store = await SqliteRoutineStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await store.saveRun(snapshot());
  });
  tearDown(() async {
    await store.close();
  });
  final changes = <String, RoutineRun Function()>{
    '실행 당시 루틴 이름': () => snapshot(revision: 2, name: '수정된 루틴'),
    '실행 당시 예상 시간': () => snapshot(revision: 2, duration: 20),
    '실행 시작 시각': () => snapshot(revision: 2, startShift: 1),
    '갱신 시각 역행': () => snapshot(revision: 2, updateMinute: 4),
    '완료 단계의 미완료 복귀': () => snapshot(revision: 2, reversed: true),
  };
  for (final entry in changes.entries) {
    test('높은 버전이라도 ${entry.key} 변경은 거부한다', () async {
      await expectLater(store.saveRun(entry.value()), throwsStateError);
      final saved = (await store.listRuns()).single;
      expect(saved.revision, 1);
      expect(saved.routineName, '아침');
      expect(saved.steps.first.status, StepStatus.completed);
    });
  }
}
