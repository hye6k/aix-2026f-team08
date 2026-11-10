import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/ports.dart';
import 'snapshot_codec.dart';
import 'run_update_guard.dart';

/// 같은 파일을 열면 sqflite 기본 singleInstance 연결을 공유할 수 있다.
/// open을 두 번 호출하는 것은 소유권 두 개나 참조 카운트를 만들지 않는다.
/// 앱에서 한 번 열어 공유하고 소유자만 마지막에 close한다.
class SqliteRoutineStore implements RoutineStore {
  SqliteRoutineStore._(this._db);
  final Database _db;
  static const _codec = SnapshotCodec();

  static Future<SqliteRoutineStore> openDefault() async =>
      open(p.join(await getDatabasesPath(), 'morning_routine.db'));

  static Future<SqliteRoutineStore> open(
    String databasePath, {
    DatabaseFactory? factory,
  }) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
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
  Future<void> saveSettings(AppSettings settings) async {
    await _db.insert('settings', {
      'id': 1,
      'payload': _codec.encodeSettings(settings),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<Routine>> listRoutines() async => (await _db.query(
    'routines',
    orderBy: 'id ASC',
  )).map((r) => _codec.decodeRoutine(r['payload']! as String)).toList();
  @override
  Future<void> saveRoutine(Routine routine) async {
    await _db.insert('routines', {
      'id': routine.id,
      'name': routine.name,
      'payload': _codec.encodeRoutine(routine),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteRoutine(String id) async {
    await _db.delete('routines', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<WakeRecord>> listWakeRecords() async => (await _db.query(
    'wake_records',
    orderBy: 'observed_at DESC, id ASC',
  )).map((r) => _codec.decodeWake(r['payload']! as String)).toList();
  @override
  Future<void> saveWakeRecord(WakeRecord record) => _db.transaction((tx) async {
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
  });

  @override
  Future<List<RoutineRun>> listRuns() async => (await _db.query(
    'routine_runs',
    orderBy: 'started_at DESC, id ASC',
  )).map((r) => _codec.decodeRun(r['payload']! as String)).toList();
  @override
  Future<void> saveRun(RoutineRun run) => _db.transaction((tx) async {
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
  });

  @override
  Future<void> close() => _db.close();
}
