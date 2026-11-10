import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/ports.dart';

import '../settings_screen_test.dart' as settings;
import '../routine_screen_test.dart' as routines;

AppSettings auditSettings({
  Duration travel = const Duration(minutes: 30),
  Duration sleep = const Duration(hours: 8),
  WakeMode mode = WakeMode.recommended,
  ClockTime? manual,
  ClockTime? start,
  ClockTime? end,
}) => AppSettings(
  arrivalTime: ClockTime(9, 0),
  travelDuration: travel,
  sleepDuration: sleep,
  wakeMode: mode,
  manualWakeTime: manual,
  detectionStart: start ?? ClockTime(7, 0),
  detectionEnd: end ?? ClockTime(8, 0),
);

class AuditStore extends settings.TestStore implements RoutineStore {
  AuditStore() {
    value = auditSettings();
  }
  final library = routines.RoutineTestStore();
  Completer<void>? settingsLoadGate;
  Completer<void>? routinesLoadGate;
  int settingsReads = 0;
  int routinesReads = 0;
  int closes = 0;
  @override
  Future<AppSettings?> loadSettings() async {
    settingsReads++;
    if (settingsLoadGate != null) await settingsLoadGate!.future;
    return super.loadSettings();
  }

  @override
  Future<List<Routine>> listRoutines() async {
    routinesReads++;
    if (routinesLoadGate != null) await routinesLoadGate!.future;
    return library.listRoutines();
  }

  @override
  Future<void> saveRoutine(Routine routine) => library.saveRoutine(routine);
  @override
  Future<void> deleteRoutine(String id) => library.deleteRoutine(id);
  @override
  Future<void> close() async {
    closes++;
  }
}

class CommitThenFailStore extends AuditStore {
  bool firstWrite = true;
  @override
  Future<void> saveRoutine(Routine routine) async {
    await super.saveRoutine(routine);
    if (firstWrite) {
      firstWrite = false;
      throw StateError('응답 실패를 가정한 저장 완료');
    }
  }
}

Future<void> auditEnter(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> auditTap(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> pickClock(
  WidgetTester tester,
  String id,
  String hour,
  String minute, {
  bool valid = true,
}) async {
  final target = find.byKey(ValueKey('time-$id'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextFormField),
  );
  await tester.enterText(fields.at(0), hour);
  await tester.enterText(fields.at(1), minute);
  await tester.tap(find.text('확인'));
  await tester.pumpAndSettle();
  expect(find.byType(TimePickerDialog), valid ? findsNothing : findsOneWidget);
  if (!valid) {
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  }
}
