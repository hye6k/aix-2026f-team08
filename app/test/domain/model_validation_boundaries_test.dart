// PR #15 박제헌(warsawmecca)님의 첨부 경계 테스트를 반영했습니다.
// 출처: https://github.com/hye6k/aix-2026f-team08/pull/15#issuecomment-6651841378
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/ports.dart';

final _at = DateTime.utc(2026, 11, 5, 7);
const _tick = Duration(microseconds: 1);
const _day = Duration(days: 1);

RoutineStep _step(
  String id, {
  Duration expected = const Duration(minutes: 10),
}) => RoutineStep(id: id, name: '준비', expected: expected);

StepExecution _execution(
  StepStatus status,
  String id, {
  DateTime? start,
  DateTime? end,
}) => StepExecution(
  step: _step(id),
  status: status,
  startedAt: status == StepStatus.pending ? null : start ?? _at,
  endedAt:
      [
        StepStatus.completed,
        StepStatus.skipped,
        StepStatus.interrupted,
      ].contains(status)
      ? end ?? _at
      : null,
);

RoutineRun _run(
  List<StepExecution> steps, {
  RunStatus status = RunStatus.running,
  DateTime? updated,
  DateTime? ended,
  int revision = 0,
}) => RoutineRun(
  id: 'run',
  routineId: 'routine',
  routineName: '준비',
  startedAt: _at,
  updatedAt: updated ?? _at,
  endedAt: ended,
  status: status,
  steps: steps,
  revision: revision,
);

void _check(bool valid, Object? Function() create, {String? reason}) => expect(
  create,
  valid ? returnsNormally : throwsArgumentError,
  reason: reason,
);

void main() {
  group('공통 값과 루틴', () {
    test('빈 문자열·공백을 각 필드에서 거부하고 유효한 원문은 보존한다', () {
      for (final value in ['', ' \t\n', '유효', ' 유효 ']) {
        final valid = value.trim().isNotEmpty;
        for (final create in <Object? Function()>[
          () => requireText(value, 'text'),
          () => RoutineStep(id: value, name: 'n', expected: _tick),
          () => RoutineStep(id: 's', name: value, expected: _tick),
          () => Routine(id: value, name: 'n', steps: [_step('s')]),
          () => Routine(id: 'r', name: value, steps: [_step('s')]),
          () => WakeRecord(
            id: value,
            observedAt: _at,
            source: WakeSource.test,
            status: WakeStatus.pending,
          ),
          () => AlarmRequest(id: value, at: _at),
          for (final field in [
            'id',
            'routineId',
            'routineName',
            'wakeRecordId',
          ])
            () => RoutineRun(
              id: field == 'id' ? value : 'r',
              routineId: field == 'routineId' ? value : 'routine',
              routineName: field == 'routineName' ? value : 'n',
              wakeRecordId: field == 'wakeRecordId' ? value : null,
              startedAt: _at,
              updatedAt: _at,
              status: RunStatus.running,
              steps: [_execution(StepStatus.active, 's')],
            ),
        ]) {
          _check(valid, create, reason: 'text=$value');
        }
      }
      expect(_step(' s ').id, ' s ');
    });

    test('기간의 음수·0·1마이크로초·24시간·24시간 초과 경계', () {
      for (final duration in [
        -_tick,
        Duration.zero,
        _tick,
        _day,
        _day + _tick,
      ]) {
        for (final allowZero in [false, true]) {
          _check(
            duration >= (allowZero ? Duration.zero : _tick) && duration <= _day,
            () => requireDuration(duration, 'duration', allowZero: allowZero),
          );
        }
        _check(
          duration > Duration.zero && duration <= _day,
          () => _step('s', expected: duration),
        );
      }
    });

    test('빈 루틴과 총시간 초과를 거부하고 정확히 24시간은 허용한다', () {
      expect(() => Routine(id: 'r', name: 'n', steps: []), throwsArgumentError);
      for (final extra in [Duration.zero, _tick]) {
        _check(
          extra == Duration.zero,
          () => Routine(
            id: 'r',
            name: 'n',
            steps: [
              _step('a', expected: const Duration(hours: 12)),
              _step('b', expected: const Duration(hours: 12) + extra),
            ],
          ),
        );
      }
    });

    test('시각 전체 분 범위·잘못된 범위·동등성·표시·로컬 날짜 보존', () {
      for (var minute = 0; minute < 1440; minute++) {
        final time = ClockTime.fromMinutes(minute);
        final same = ClockTime(minute ~/ 60, minute % 60);
        expect(time.minutes, minute);
        expect(time, same);
        expect(time.hashCode, same.hashCode);
        expect(
          time.toString(),
          '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}',
        );
      }
      for (final hour in [-1, 0, 23, 24]) {
        for (final minute in [-1, 0, 59, 60]) {
          _check(
            hour >= 0 && hour < 24 && minute >= 0 && minute < 60,
            () => ClockTime(hour, minute),
          );
        }
      }
      for (final value in [-1, 1440]) {
        expect(() => ClockTime.fromMinutes(value), throwsArgumentError);
      }
      expect(ClockTime(0, 0), isNot(ClockTime(0, 1)));
      expect(ClockTime(0, 0), isNot('00:00'));
      final day = DateTime(2026, 12, 31, 23, 59);
      final result = ClockTime(7, 30).on(day);
      expect(result, DateTime(2026, 12, 31, 7, 30));
      expect(result.isUtc, isFalse);
    });
  });

  group('설정', () {
    AppSettings settings({
      Duration travel = Duration.zero,
      Duration sleep = const Duration(hours: 8),
      WakeMode mode = WakeMode.recommended,
      ClockTime? manual,
      int start = 360,
      int end = 540,
    }) => AppSettings(
      arrivalTime: ClockTime(9, 0),
      travelDuration: travel,
      sleepDuration: sleep,
      wakeMode: mode,
      manualWakeTime: manual,
      detectionStart: ClockTime.fromMinutes(start),
      detectionEnd: ClockTime.fromMinutes(end),
    );

    test('이동·수면 경계와 기상 모드별 수동 시각 조합', () {
      for (final travel in [-_tick, Duration.zero, _tick, _day, _day + _tick]) {
        for (final sleep in [
          -_tick,
          Duration.zero,
          _tick,
          _day,
          _day + _tick,
        ]) {
          for (final mode in WakeMode.values) {
            for (final manual in [null, ClockTime(7, 0)]) {
              _check(
                travel >= Duration.zero &&
                    travel <= _day &&
                    sleep > Duration.zero &&
                    sleep <= _day &&
                    (mode != WakeMode.manual || manual != null),
                () => settings(
                  travel: travel,
                  sleep: sleep,
                  mode: mode,
                  manual: manual,
                ),
              );
            }
          }
        }
      }
    });

    test('일반·자정 통과·자정 경계 구간의 모든 분: 시작 포함, 끝 제외', () {
      for (final bounds in [
        [360, 540],
        [1320, 120],
        [0, 1439],
        [1439, 0],
      ]) {
        final value = settings(start: bounds[0], end: bounds[1]);
        final length = (bounds[1] - bounds[0] + 1440) % 1440;
        for (var minute = 0; minute < 1440; minute++) {
          expect(
            value.containsDetectionTime(
              DateTime(2026, 11, 5, minute ~/ 60, minute % 60, 59),
            ),
            (minute - bounds[0] + 1440) % 1440 < length,
            reason: '$bounds minute=$minute',
          );
        }
      }
      expect(() => settings(start: 0, end: 0), throwsArgumentError);
    });
  });

  test('기상 기록: 모든 출처·상태와 시각 유무·선후 조합', () {
    final times = <DateTime?>[null, _at.subtract(_tick), _at, _at.add(_tick)];
    for (final source in WakeSource.values) {
      for (final status in WakeStatus.values) {
        for (final decided in times) {
          for (final wake in times) {
            final valid =
                (source != WakeSource.manual ||
                    status == WakeStatus.confirmed) &&
                (decided == null || !decided.isBefore(_at)) &&
                switch (status) {
                  WakeStatus.pending => decided == null && wake == null,
                  WakeStatus.cancelled => decided != null && wake == null,
                  WakeStatus.confirmed =>
                    decided != null && wake != null && !wake.isAfter(decided),
                };
            _check(
              valid,
              () => WakeRecord(
                id: 'w',
                observedAt: _at,
                source: source,
                status: status,
                decidedAt: decided,
                wakeAt: wake,
              ),
              reason: '$source $status decided=$decided wake=$wake',
            );
          }
        }
      }
    }
  });

  test('단계 실행: 모든 상태와 시작·종료 시각의 유무·선후 및 실제 소요', () {
    final times = <DateTime?>[null, _at.subtract(_tick), _at, _at.add(_tick)];
    for (final status in StepStatus.values) {
      for (final start in times) {
        for (final end in times) {
          final valid = switch (status) {
            StepStatus.pending => start == null && end == null,
            StepStatus.active => start != null && end == null,
            _ => start != null && end != null && !end.isBefore(start),
          };
          StepExecution create() => StepExecution(
            step: _step('s'),
            status: status,
            startedAt: start,
            endedAt: end,
          );
          _check(valid, create, reason: '$status start=$start end=$end');
          if (valid) {
            expect(create().actual, end?.difference(start!));
          }
        }
      }
    }
  });

  group('실행 스냅샷', () {
    test('길이 1~4의 모든 상태 배열: 진행·완료·중단별 순서와 개수', () {
      // 허용 문법: 처리* 활성 대기*, 처리+, 처리* 중단 대기*.
      // 처리 = completed 또는 skipped. 각 단계의 시각은 같은 순간으로 둔다.
      for (var length = 1; length <= 4; length++) {
        var count = 1;
        for (var i = 0; i < length; i++) {
          count *= 5;
        }
        for (var code = 0; code < count; code++) {
          var value = code;
          final statuses = <StepStatus>[];
          for (var i = 0; i < length; i++) {
            statuses.add(StepStatus.values[value % 5]);
            value ~/= 5;
          }
          final pattern = statuses
              .map(
                (s) => switch (s) {
                  StepStatus.completed || StepStatus.skipped => 'T',
                  StepStatus.active => 'A',
                  StepStatus.interrupted => 'I',
                  StepStatus.pending => 'P',
                },
              )
              .join();
          final steps = [
            for (var i = 0; i < length; i++) _execution(statuses[i], '$i'),
          ];
          for (final status in RunStatus.values) {
            final grammar = switch (status) {
              RunStatus.running => RegExp(r'^T*AP*$'),
              RunStatus.completed => RegExp(r'^T+$'),
              RunStatus.stopped => RegExp(r'^T*IP*$'),
            };
            _check(
              grammar.hasMatch(pattern),
              () => _run(
                steps,
                status: status,
                ended: status == RunStatus.running ? null : _at,
              ),
              reason: '$status $statuses',
            );
          }
        }
      }
    });

    test('상태별 종료 시각 유무·갱신 전후·음수 버전 조합', () {
      for (final status in RunStatus.values) {
        for (final updated in [_at.subtract(_tick), _at, _at.add(_tick)]) {
          for (final ended in [
            null,
            _at.subtract(_tick),
            _at,
            _at.add(_tick),
          ]) {
            for (final revision in [-1, 0, 1]) {
              final stepStatus = switch (status) {
                RunStatus.running => StepStatus.active,
                RunStatus.completed => StepStatus.completed,
                RunStatus.stopped => StepStatus.interrupted,
              };
              final valid =
                  revision >= 0 &&
                  !updated.isBefore(_at) &&
                  (status == RunStatus.running
                      ? ended == null
                      : ended != null &&
                            ended.isAtSameMomentAs(updated) &&
                            !ended.isBefore(_at));
              _check(
                valid,
                () => _run(
                  [_execution(stepStatus, 's', end: ended)],
                  status: status,
                  updated: updated,
                  ended: ended,
                  revision: revision,
                ),
                reason:
                    '$status updated=$updated ended=$ended revision=$revision',
              );
            }
          }
        }
      }
    });

    test('빈 목록과 서로 다른 객체의 중복 단계 ID를 거부한다', () {
      expect(() => _run([]), throwsArgumentError);
      expect(
        () => _run([
          _execution(StepStatus.completed, 's'),
          _execution(StepStatus.active, 's'),
        ]),
        throwsArgumentError,
      );
    });

    test('단계 시작은 실행 시작~갱신 범위 안이어야 한다', () {
      for (final start in [_at.subtract(_tick), _at, _at.add(_tick)]) {
        _check(
          start == _at,
          () => _run([_execution(StepStatus.active, 's', start: start)]),
        );
      }
    });

    test('단계 간 겹침은 거부하고 동일 시각 및 시간 간격은 허용한다', () {
      final boundary = _at.add(const Duration(minutes: 10));
      for (final next in [
        boundary.subtract(_tick),
        boundary,
        boundary.add(_tick),
      ]) {
        _check(
          !next.isBefore(boundary),
          () => _run([
            _execution(StepStatus.completed, 'a', end: boundary),
            _execution(StepStatus.active, 'b', start: next),
          ], updated: boundary.add(_tick)),
        );
      }
    });

    test('갱신보다 늦은 단계 종료는 거부한다', () {
      expect(
        () => _run(
          [_execution(StepStatus.completed, 's', end: _at.add(_tick))],
          status: RunStatus.completed,
          ended: _at,
        ),
        throwsArgumentError,
      );
    });

    test('정상 완료·건너뛰기와 실행 목록 복사·수정 금지 및 활성 단계 조회', () {
      final source = [
        _execution(StepStatus.completed, 'a'),
        _execution(StepStatus.active, 'b'),
      ];
      final run = _run(source);
      expect(run.activeStep, same(source[1]));
      source.clear();
      expect(run.steps, hasLength(2));
      expect(() => run.steps.clear(), throwsUnsupportedError);
      expect(
        () => run.steps[0] = _execution(StepStatus.pending, 'c'),
        throwsUnsupportedError,
      );
      final completed = _run(
        [
          _execution(StepStatus.completed, 'a'),
          _execution(StepStatus.skipped, 'b'),
        ],
        status: RunStatus.completed,
        ended: _at,
      );
      expect(completed.activeStep, isNull);
      expect(completed.revision, 0);
      expect(completed.wakeRecordId, isNull);
    });
  });

  group('계획 경계', () {
    DailyPlan plan({
      Duration preparation = const Duration(hours: 1),
      Duration travel = const Duration(minutes: 30),
      Duration sleep = const Duration(hours: 8),
      Duration wakeOffset = Duration.zero,
      Duration alarmOffset = Duration.zero,
    }) {
      final alarm = _at.add(alarmOffset);
      final departure = _at.add(preparation);
      return DailyPlan(
        arrivalAt: departure.add(travel),
        departureAt: departure,
        recommendedWakeAt: _at.add(wakeOffset),
        alarmAt: alarm,
        bedtimeAt: alarm.subtract(sleep),
        preparation: preparation,
      );
    }

    for (final field in ['preparation', 'travel', 'sleep']) {
      test('$field: 음수·0·1마이크로초·정확히 24시간·초과', () {
        for (final duration in [
          -_tick,
          Duration.zero,
          _tick,
          _day,
          _day + _tick,
        ]) {
          final valid =
              duration >= (field == 'travel' ? Duration.zero : _tick) &&
              duration <= _day;
          _check(
            valid,
            () => switch (field) {
              'preparation' => plan(preparation: duration),
              'travel' => plan(travel: duration),
              _ => plan(sleep: duration),
            },
            reason: '$field=$duration',
          );
        }
      });
    }

    test('권장 기상의 1마이크로초 오차도 거부한다', () {
      for (final offset in [-_tick, Duration.zero, _tick]) {
        _check(offset == Duration.zero, () => plan(wakeOffset: offset));
      }
    });

    test('실제 알람은 권장보다 이르거나 늦어도 수면 관계만 맞으면 허용한다', () {
      for (final offset in [
        const Duration(hours: -2),
        Duration.zero,
        const Duration(hours: 5),
      ]) {
        final result = plan(alarmOffset: offset);
        expect(result.alarmAt, _at.add(offset));
        expect(
          result.alarmAt.difference(result.bedtimeAt),
          const Duration(hours: 8),
        );
      }
    });
  });

  test('플랫폼 전달 모델은 ID 검증 외 시각과 출처를 보존한다', () {
    final request = AlarmRequest(id: ' alarm ', at: _at);
    expect(request.id, ' alarm ');
    expect(request.at, _at);
    for (final source in WakeSource.values) {
      final signal = ActivitySignal(at: _at, source: source);
      expect(signal.at, _at);
      expect(signal.source, source);
    }
  });
}
