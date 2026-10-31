import 'dart:convert';

import '../domain/models.dart';

class SnapshotCodec {
  const SnapshotCodec();
  String _encode(Map<String, Object?> data) =>
      jsonEncode({'schema': 1, ...data});
  Map<String, dynamic> _decode(String payload) {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    if (data['schema'] != 1) {
      throw const FormatException('지원하지 않는 저장 형식입니다.');
    }
    return data;
  }

  DateTime? _at(Object? value) => value == null
      ? null
      : DateTime.fromMicrosecondsSinceEpoch(value as int, isUtc: true);
  Map<String, Object?> _step(RoutineStep s) => {
    'id': s.id,
    'name': s.name,
    'expected': s.expected.inMicroseconds,
  };
  RoutineStep _readStep(Map<String, dynamic> s) => RoutineStep(
    id: s['id'] as String,
    name: s['name'] as String,
    expected: Duration(microseconds: s['expected'] as int),
  );

  String encodeSettings(AppSettings s) => _encode({
    'arrival': s.arrivalTime.minutes,
    'travel': s.travelDuration.inMicroseconds,
    'sleep': s.sleepDuration.inMicroseconds,
    'mode': s.wakeMode.name,
    'manual': s.manualWakeTime?.minutes,
    'detection_start': s.detectionStart.minutes,
    'detection_end': s.detectionEnd.minutes,
  });
  AppSettings decodeSettings(String payload) {
    final s = _decode(payload);
    return AppSettings(
      arrivalTime: ClockTime.fromMinutes(s['arrival'] as int),
      travelDuration: Duration(microseconds: s['travel'] as int),
      sleepDuration: Duration(microseconds: s['sleep'] as int),
      wakeMode: WakeMode.values.byName(s['mode'] as String),
      manualWakeTime: s['manual'] == null
          ? null
          : ClockTime.fromMinutes(s['manual'] as int),
      detectionStart: ClockTime.fromMinutes(s['detection_start'] as int),
      detectionEnd: ClockTime.fromMinutes(s['detection_end'] as int),
    );
  }

  String encodeRoutine(Routine r) => _encode({
    'id': r.id,
    'name': r.name,
    'steps': r.steps.map(_step).toList(),
  });
  Routine decodeRoutine(String payload) {
    final r = _decode(payload);
    return Routine(
      id: r['id'] as String,
      name: r['name'] as String,
      steps: (r['steps'] as List<dynamic>)
          .map((s) => _readStep(s as Map<String, dynamic>))
          .toList(),
    );
  }

  String encodeWake(WakeRecord w) => _encode({
    'id': w.id,
    'observed': w.observedAt.microsecondsSinceEpoch,
    'source': w.source.name,
    'status': w.status.name,
    'decided': w.decidedAt?.microsecondsSinceEpoch,
    'wake': w.wakeAt?.microsecondsSinceEpoch,
  });
  WakeRecord decodeWake(String payload) {
    final w = _decode(payload);
    return WakeRecord(
      id: w['id'] as String,
      observedAt: _at(w['observed'])!,
      source: WakeSource.values.byName(w['source'] as String),
      status: WakeStatus.values.byName(w['status'] as String),
      decidedAt: _at(w['decided']),
      wakeAt: _at(w['wake']),
    );
  }

  String encodeRun(RoutineRun r) => _encode({
    'id': r.id,
    'routine_id': r.routineId,
    'routine_name': r.routineName,
    'wake_record_id': r.wakeRecordId,
    'started': r.startedAt.microsecondsSinceEpoch,
    'updated': r.updatedAt.microsecondsSinceEpoch,
    'ended': r.endedAt?.microsecondsSinceEpoch,
    'status': r.status.name,
    'revision': r.revision,
    'steps': [
      for (final s in r.steps)
        {
          ..._step(s.step),
          'status': s.status.name,
          'started': s.startedAt?.microsecondsSinceEpoch,
          'ended': s.endedAt?.microsecondsSinceEpoch,
        },
    ],
  });
  RoutineRun decodeRun(String payload) {
    final r = _decode(payload);
    return RoutineRun(
      id: r['id'] as String,
      routineId: r['routine_id'] as String,
      routineName: r['routine_name'] as String,
      wakeRecordId: r['wake_record_id'] as String?,
      startedAt: _at(r['started'])!,
      updatedAt: _at(r['updated'])!,
      endedAt: _at(r['ended']),
      status: RunStatus.values.byName(r['status'] as String),
      revision: r['revision'] as int,
      steps: (r['steps'] as List<dynamic>).map((raw) {
        final s = raw as Map<String, dynamic>;
        return StepExecution(
          step: _readStep(s),
          status: StepStatus.values.byName(s['status'] as String),
          startedAt: _at(s['started']),
          endedAt: _at(s['ended']),
        );
      }).toList(),
    );
  }
}
