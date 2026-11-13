import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../application/session_port.dart';

import 'snapshot_codec.dart';
import 'run_update_guard.dart';

/// 같은 파일을 열면 sqflite 기본 singleInstance 연결을 공유할 수 있다.
/// open을 두 번 호출하는 것은 소유권 두 개나 참조 카운트를 만들지 않는다.
/// 앱에서 한 번 열어 공유하고 소유자만 마지막에 close한다.
class SqliteRoutineStore implements SessionStore {
  SqliteRoutineStore._(this._db);
  final Database _db;
  static const _codec = SnapshotCodec();
  static const _sessionTable =
      'CREATE TABLE session_context (id INTEGER PRIMARY KEY CHECK(id = 1), revision INTEGER NOT NULL CHECK(revision >= 0), payload TEXT NOT NULL)';

  static Future<SqliteRoutineStore> openDefault() async =>
      open(p.join(await getDatabasesPath(), 'morning_routine.db'));

  static Future<SqliteRoutineStore> open(
    String databasePath, {
    DatabaseFactory? factory,
  }) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await db.execute(_sessionTable);
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          batch.execute(
            'CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK(id = 1), payload TEXT NOT NULL)',
          );
          batch.execute(
            'CREATE TABLE routines (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, payload TEXT NOT NULL)',
          );
          batch.execute(
            "CREATE TABLE wake_records (id TEXT PRIMARY KEY NOT NULL, observed_at INTEGER NOT NULL, status TEXT NOT NULL CHECK(status IN ('pending','confirmed','cancelled')), payload TEXT NOT NULL)",
          );
          batch.execute(
            "CREATE TABLE routine_runs (id TEXT PRIMARY KEY NOT NULL, started_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, status TEXT NOT NULL CHECK(status IN ('running','completed','stopped')), revision INTEGER NOT NULL CHECK(revision >= 0), payload TEXT NOT NULL)",
          );
          batch.execute(
            'CREATE INDEX wake_time ON wake_records(observed_at DESC)',
          );
          batch.execute(
            'CREATE INDEX run_status_time ON routine_runs(status, started_at DESC)',
          );
          batch.execute(_sessionTable);
          await batch.commit(noResult: true);
        },
      ),
    );
    return SqliteRoutineStore._(db);
  }

  @override
  Future<AppSettings?> loadSettings() async {
    final rows = await _db.query('settings', where: 'id = ?', whereArgs: [1]);
    return rows.isEmpty
        ? null
        : _codec.decodeSettings(rows.single['payload']! as String);
  }

  @override
  Future<void> saveSettings(AppSettings settings) =>
      _db.transaction((tx) async {
        if ((await tx.query('session_context')).isNotEmpty) {
          throw StateError('활성 계획의 설정은 세션 API로 저장하세요.');
        }
        await tx.insert('settings', {
          'id': 1,
          'payload': _codec.encodeSettings(settings),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });

  @override
  Future<List<Routine>> listRoutines() async => (await _db.query(
    'routines',
    orderBy: 'id ASC',
  )).map((r) => _codec.decodeRoutine(r['payload']! as String)).toList();
  @override
  Future<void> saveRoutine(Routine routine) => _db.transaction((tx) async {
    await _rejectSelectedRoutine(tx, routine.id);
    await tx.insert('routines', {
      'id': routine.id,
      'name': routine.name,
      'payload': _codec.encodeRoutine(routine),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  @override
  Future<void> deleteRoutine(String id) => _db.transaction((tx) async {
    await _rejectSelectedRoutine(tx, id);
    await tx.delete('routines', where: 'id = ?', whereArgs: [id]);
  });

  static Future<void> _rejectSelectedRoutine(
    DatabaseExecutor tx,
    String id,
  ) async {
    final active = await tx.query(
      'session_context',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (active.isNotEmpty &&
        (jsonDecode(active.single['payload']! as String)
                as Map<String, dynamic>)['routineId'] ==
            id) {
      throw StateError('현재 계획에서 사용하는 루틴입니다. 다른 루틴을 선택한 뒤 삭제하거나 세션 API로 수정하세요.');
    }
  }

  @override
  Future<List<WakeRecord>> listWakeRecords() async => (await _db.query(
    'wake_records',
    orderBy: 'observed_at DESC, id ASC',
  )).map((r) => _codec.decodeWake(r['payload']! as String)).toList();
  @override
  Future<void> saveWakeRecord(WakeRecord record) =>
      _db.transaction((tx) => _saveWake(tx, record));

  static Future<void> _saveWake(DatabaseExecutor tx, WakeRecord record) async {
    final payload = _codec.encodeWake(record);
    final old = await tx.query(
      'wake_records',
      where: 'id = ?',
      whereArgs: [record.id],
    );
    if (old.isNotEmpty) {
      if (old.single['payload'] == payload) {
        return;
      }
      final existing = _codec.decodeWake(old.single['payload']! as String);
      if (existing.status != WakeStatus.pending ||
          !existing.observedAt.isAtSameMomentAs(record.observedAt) ||
          existing.source != record.source) {
        throw StateError('다른 후보 또는 확정·취소된 기록을 덮어쓸 수 없습니다.');
      }
    }
    await tx.insert('wake_records', {
      'id': record.id,
      'observed_at': record.observedAt.microsecondsSinceEpoch,
      'status': record.status.name,
      'payload': payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<RoutineRun>> listRuns() async => (await _db.query(
    'routine_runs',
    orderBy: 'started_at DESC, id ASC',
  )).map((r) => _codec.decodeRun(r['payload']! as String)).toList();
  @override
  Future<void> saveRun(RoutineRun run) =>
      _db.transaction((tx) => _saveRun(tx, run));

  static Future<void> _saveRun(DatabaseExecutor tx, RoutineRun run) async {
    final payload = _codec.encodeRun(run);
    final old = await tx.query(
      'routine_runs',
      where: 'id = ?',
      whereArgs: [run.id],
    );
    if (old.isNotEmpty) {
      if (old.single['payload'] == payload) {
        return;
      }
      validateRunUpdate(
        _codec.decodeRun(old.single['payload']! as String),
        run,
      );
    }
    await tx.insert('routine_runs', {
      'id': run.id,
      'started_at': run.startedAt.microsecondsSinceEpoch,
      'updated_at': run.updatedAt.microsecondsSinceEpoch,
      'status': run.status.name,
      'revision': run.revision,
      'payload': payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<SessionCheckpoint?> loadSession() async {
    final rows = await _db.query(
      'session_context',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (rows.isEmpty) return null;
    final data =
        jsonDecode(rows.single['payload']! as String) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('지원하지 않는 세션 버전입니다.');
    if (data['utc'] is! bool) {
      throw const FormatException('날짜 시간대 형식이 올바르지 않습니다.');
    }
    final day = (data['day'] as List).cast<int>();
    if (day.length != 3) throw const FormatException('목표 날짜가 올바르지 않습니다.');
    final arrivalDay = data['utc'] == true
        ? DateTime.utc(day[0], day[1], day[2])
        : DateTime(day[0], day[1], day[2]);
    if (arrivalDay.year != day[0] ||
        arrivalDay.month != day[1] ||
        arrivalDay.day != day[2]) {
      throw const FormatException('존재하지 않는 날짜입니다.');
    }
    return SessionCheckpoint(
      revision: rows.single['revision']! as int,
      routineId: data['routineId'] as String,
      arrivalDay: arrivalDay,
      wakeId: data['wakeId'] as String?,
      runId: data['runId'] as String?,
      cancellationPending: data['cancellationPending'] as bool,
      alarmUpdatePending: (data['alarmUpdatePending'] ?? false) as bool,
      alarmPendingAt: data['alarmPendingAt'] == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(
              data['alarmPendingAt'] as int,
              isUtc: true,
            ),
    );
  }

  @override
  Future<void> commitSession(
    SessionCheckpoint checkpoint, {
    AppSettings? settings,
    Routine? routine,
    WakeRecord? wake,
    RoutineRun? run,
  }) => _db.transaction((tx) async {
    final old = await tx.query(
      'session_context',
      columns: ['revision'],
      where: 'id = ?',
      whereArgs: [1],
    );
    if (old.isNotEmpty &&
        checkpoint.revision <= (old.single['revision']! as int)) {
      throw StateError('오래된 세션을 덮어쓸 수 없습니다.');
    }
    if (settings != null) {
      await tx.insert('settings', {
        'id': 1,
        'payload': _codec.encodeSettings(settings),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (routine != null) {
      await tx.insert('routines', {
        'id': routine.id,
        'name': routine.name,
        'payload': _codec.encodeRoutine(routine),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (wake != null) await _saveWake(tx, wake);
    if (run != null) await _saveRun(tx, run);
    final selected = await tx.query(
      'routines',
      where: 'id = ?',
      whereArgs: [checkpoint.routineId],
    );
    if (selected.isEmpty || (await tx.query('settings')).isEmpty) {
      throw StateError('활성 계획에 필요한 설정·루틴이 없습니다.');
    }
    WakeRecord? referencedWake;
    if (checkpoint.wakeId != null) {
      final rows = await tx.query(
        'wake_records',
        where: 'id = ?',
        whereArgs: [checkpoint.wakeId],
      );
      if (rows.isEmpty) throw StateError('활성 기상 참조가 없습니다.');
      referencedWake = _codec.decodeWake(rows.single['payload']! as String);
    }
    if (checkpoint.cancellationPending &&
        referencedWake?.status != WakeStatus.confirmed) {
      throw StateError('알람 취소 대기에는 확정된 기상이 필요합니다.');
    }
    if (checkpoint.runId != null) {
      final rows = await tx.query(
        'routine_runs',
        where: 'id = ?',
        whereArgs: [checkpoint.runId],
      );
      if (rows.isEmpty ||
          _codec.decodeRun(rows.single['payload']! as String).routineId !=
              checkpoint.routineId) {
        throw StateError('활성 루틴 실행 참조가 올바르지 않습니다.');
      }
    }
    final day = checkpoint.arrivalDay;
    await tx.insert('session_context', {
      'id': 1,
      'revision': checkpoint.revision,
      'payload': jsonEncode({
        'version': 1,
        'routineId': checkpoint.routineId,
        'day': [day.year, day.month, day.day],
        'utc': day.isUtc,
        'wakeId': checkpoint.wakeId,
        'runId': checkpoint.runId,
        'cancellationPending': checkpoint.cancellationPending,
        'alarmUpdatePending': checkpoint.alarmUpdatePending,
        'alarmPendingAt': checkpoint.alarmPendingAt?.microsecondsSinceEpoch,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  @override
  Future<void> close() => _db.close();
}
