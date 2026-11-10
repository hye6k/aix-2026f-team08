import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/app.dart';
import 'package:morning_routine/data/sqlite_store.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'settings_screen_test.dart' as settings;
import 'routine_screen_test.dart' as routines;
import 'support/ui_audit_support.dart';

Future<void> pumpIo(WidgetTester tester, Finder ready) async {
  for (var i = 0; i < 150; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    if (ready.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  expect(ready, findsWidgets);
}

void main() {
  sqfliteFfiInit();
  for (final routinePage in [false, true]) {
    final page = routinePage ? 'T05' : 'T04';
    for (final operation in ['조회', '저장', if (routinePage) '삭제']) {
      testWidgets('$page 실제 닫힌 SQLite $operation 오류 전달과 원본 보호', (tester) async {
        await tester.runAsync(() async {
          final dir = await Directory.systemTemp.createTemp('ui-real-error-');
          final file = '${dir.path}/app.db';
          var store = await SqliteRoutineStore.open(
            file,
            factory: databaseFactoryFfi,
          );
          addTearDown(() async {
            await store.close();
            await dir.delete(recursive: true);
          });
          await store.saveSettings(auditSettings());
          await store.saveRoutine(routines.sample());
          if (operation == '조회') await store.close();
          if (routinePage) {
            await routines.openLibrary(tester, store);
            await pumpIo(
              tester,
              find.text(operation == '조회' ? '다시 불러오기' : '등교'),
            );
          } else {
            await settings.open(tester, store);
            await pumpIo(
              tester,
              find.text(operation == '조회' ? '다시 불러오기' : '저장된 설정을 수정할 수 있어요.'),
            );
          }
          if (operation == '조회') {
            expect(find.textContaining('아직 등록한 루틴'), findsNothing);
            expect(find.text('목표 도착 시각과 수면·기상 시간을 설정해 주세요.'), findsNothing);
          } else {
            if (operation == '저장' && routinePage) await auditTap(tester, '등교');
            await store.close();
            if (operation == '삭제') {
              await routines.icon(tester, '등교 삭제');
              await auditTap(tester, '삭제');
              await pumpIo(tester, find.text('루틴을 삭제하지 못했어요. 다시 시도해 주세요.'));
              expect(find.text('등교'), findsOneWidget);
              expect(find.text('루틴을 삭제했어요.'), findsNothing);
            } else if (routinePage) {
              await auditEnter(tester, '루틴명', '변경 실패');
              await auditTap(tester, '루틴 저장');
              await pumpIo(tester, find.text('다시 저장'));
              expect(
                find.widgetWithText(TextFormField, '변경 실패'),
                findsOneWidget,
              );
              expect(find.text('루틴을 저장했어요.'), findsNothing);
            } else {
              await auditEnter(tester, '이동 시간, 분', '45');
              await auditTap(tester, '설정 저장');
              await pumpIo(tester, find.text('다시 저장'));
              expect(find.widgetWithText(TextFormField, '45'), findsOneWidget);
              expect(find.text('설정을 저장했어요.'), findsNothing);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          store = await SqliteRoutineStore.open(
            file,
            factory: databaseFactoryFfi,
          );
          expect(
            (await store.loadSettings())!.travelDuration,
            const Duration(minutes: 30),
          );
          expect((await store.listRoutines()).single.name, '등교');
        });
      });
    }
    testWidgets('$page 실제 손상된 저장 데이터는 초기화하지 않고 조회 실패 표시', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('ui-corrupt-');
        final file = '${dir.path}/app.db';
        final store = await SqliteRoutineStore.open(
          file,
          factory: databaseFactoryFfi,
        );
        addTearDown(() async {
          await store.close();
          await dir.delete(recursive: true);
        });
        await store.saveSettings(auditSettings());
        await store.saveRoutine(routines.sample());
        final db = await databaseFactoryFfi.openDatabase(file);
        final table = routinePage ? 'routines' : 'settings';
        await db.rawUpdate('UPDATE $table SET payload = ?', ['{"schema":999}']);
        if (routinePage) {
          await routines.openLibrary(tester, store);
        } else {
          await settings.open(tester, store);
        }
        await pumpIo(tester, find.text('다시 불러오기'));
        expect(find.textContaining('아직 등록한 루틴'), findsNothing);
        expect((await db.query(table)).single['payload'], '{"schema":999}');
      });
    });
  }
  testWidgets('T04 실제 SQLite 신규 UI 입력·모드·감지 경계 재개방 복원', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('t04-new-db-');
      final file = '${dir.path}/app.db';
      var store = await SqliteRoutineStore.open(
        file,
        factory: databaseFactoryFfi,
      );
      addTearDown(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
      await settings.open(tester, store);
      await pumpIo(tester, find.text('목표 도착 시각과 수면·기상 시간을 설정해 주세요.'));
      await pickClock(tester, 'arrival', '00', '00');
      await auditEnter(tester, '이동 시간, 시간', '0');
      await auditEnter(tester, '이동 시간, 분', '0');
      await auditEnter(tester, '수면 시간, 시간', '24');
      await auditEnter(tester, '수면 시간, 분', '0');
      await auditTap(tester, '직접 지정');
      await pickClock(tester, 'manual', '23', '59');
      await pickClock(tester, 'start', '23', '00');
      await pickClock(tester, 'end', '01', '00');
      await auditTap(tester, '설정 저장');
      await pumpIo(tester, find.text('설정을 저장했어요.'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await store.close();
      store = await SqliteRoutineStore.open(file, factory: databaseFactoryFfi);
      final restored = (await store.loadSettings())!;
      expect(restored.arrivalTime, ClockTime(0, 0));
      expect(restored.travelDuration, Duration.zero);
      expect(restored.sleepDuration, const Duration(hours: 24));
      expect(restored.manualWakeTime, ClockTime(23, 59));
      expect(restored.wakeMode, WakeMode.manual);
      expect(restored.detectionStart, ClockTime(23, 0));
      expect(restored.detectionEnd, ClockTime(1, 0));
      await settings.open(tester, store);
      await pumpIo(tester, find.text('23:59'));
      expect(find.text('00:00'), findsOneWidget);
    });
  });
  testWidgets('실제 SQLite 파일 열기 실패도 신규 화면으로 바꾸지 않는다', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('ui-invalid-path-');
      addTearDown(() => dir.delete(recursive: true));
      await tester.pumpWidget(
        MorningRoutineApp(
          openStore: () =>
              SqliteRoutineStore.open(dir.path, factory: databaseFactoryFfi),
        ),
      );
      await auditTap(tester, '시간 설정');
      await pumpIo(tester, find.text('다시 불러오기'));
      expect(find.text('목표 도착 시각과 수면·기상 시간을 설정해 주세요.'), findsNothing);
    });
  });
}
