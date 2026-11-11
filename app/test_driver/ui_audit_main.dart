// Android 수동/ADB 점검 전용 진입점. 일반 앱 DB를 사용하지 않는다.
// flutter run -t test_driver/ui_audit_main.dart --dart-define=UI_AUDIT_DB=ui_audit_example.db
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:morning_routine/app/app.dart';
import 'package:morning_routine/data/sqlite_store.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const name = String.fromEnvironment(
    'UI_AUDIT_DB',
    defaultValue: 'ui_audit_t04_t05.db',
  );
  if (!RegExp(r'^ui_audit_[a-zA-Z0-9_]+\.db$').hasMatch(name)) {
    throw ArgumentError('점검 DB 이름은 ui_audit_로 시작해야 합니다.');
  }
  final file = p.join(await getDatabasesPath(), name);
  final existed = await File(file).exists();
  final store = await SqliteRoutineStore.open(file);
  if (!existed) {
    await store.saveSettings(
      AppSettings(
        arrivalTime: ClockTime(9, 0),
        travelDuration: const Duration(minutes: 30),
        sleepDuration: const Duration(hours: 8),
        wakeMode: WakeMode.recommended,
        detectionStart: ClockTime(7, 0),
        detectionEnd: ClockTime(8, 0),
      ),
    );
    final routine = Routine(
      id: 'audit_seed',
      name: 'Seed routine',
      steps: [
        RoutineStep(
          id: 'audit_wash',
          name: 'Wash',
          expected: const Duration(minutes: 20),
        ),
        RoutineStep(
          id: 'audit_meal',
          name: 'Meal',
          expected: const Duration(minutes: 15),
        ),
      ],
    );
    await store.saveRoutine(routine);
    final at = DateTime.utc(2026, 11, 10, 7);
    await store.saveRun(
      RoutineRun(
        id: 'audit_past',
        routineId: routine.id,
        routineName: routine.name,
        startedAt: at,
        updatedAt: at,
        endedAt: at,
        status: RunStatus.completed,
        steps: [
          for (final step in routine.steps)
            StepExecution(
              step: step,
              status: StepStatus.completed,
              startedAt: at,
              endedAt: at,
            ),
        ],
      ),
    );
  }
  final settings = (await store.loadSettings())!;
  final routines = await store.listRoutines();
  final runs = await store.listRuns();
  debugPrint(
    'UI_AUDIT_SNAPSHOT ${jsonEncode({
      'database': name,
      'arrival': settings.arrivalTime.toString(),
      'travelMinutes': settings.travelDuration.inMinutes,
      'sleepMinutes': settings.sleepDuration.inMinutes,
      'mode': settings.wakeMode.name,
      'manual': settings.manualWakeTime?.toString(),
      'start': settings.detectionStart.toString(),
      'end': settings.detectionEnd.toString(),
      'routines': [
        for (final r in routines) {
            'id': r.id,
            'name': r.name,
            'steps': [
              for (final s in r.steps) {'id': s.id, 'name': s.name, 'minutes': s.expected.inMinutes},
            ],
          },
      ],
      'runs': [
        for (final r in runs) {'id': r.id, 'name': r.routineName, 'steps': r.steps.map((s) => s.step.name).toList()},
      ],
    })}',
  );
  runApp(MorningRoutineApp(store: store));
}
