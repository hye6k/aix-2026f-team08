import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/domain/models.dart';
import 'package:morning_routine/domain/wake_tracker.dart';

void main() {
  final tracker = WakeTracker();
  final at = DateTime.utc(2026, 11, 1, 7);
  AppSettings settings({bool overnight = false}) => AppSettings(
    arrivalTime: ClockTime(9, 0),
    travelDuration: Duration.zero,
    sleepDuration: const Duration(hours: 8),
    wakeMode: WakeMode.recommended,
    detectionStart: ClockTime(overnight ? 23 : 6, 0),
    detectionEnd: ClockTime(overnight ? 2 : 9, 0),
  );
  WakeRecord candidate() =>
      tracker.detect(id: 'w', at: at, settings: settings())!;

  test('신호는 미확인 후보이며 반복 신호가 확정하거나 중복 생성하지 않는다', () {
    final first = candidate();
    final repeated = tracker.detect(
      id: 'other',
      at: at.add(const Duration(minutes: 10)),
      settings: settings(),
      previous: first,
    );
    expect(repeated, same(first));
    expect(first.status, WakeStatus.pending);
    expect(first.wakeAt, isNull);
  });
  test('구간 시작은 포함하고 끝은 제외하며 야간 구간을 처리한다', () {
    expect(
      tracker.detect(
        id: 'x',
        at: DateTime.utc(2026, 11, 1, 6),
        settings: settings(),
      ),
      isNotNull,
    );
    expect(
      tracker.detect(
        id: 'x',
        at: DateTime.utc(2026, 11, 1, 9),
        settings: settings(),
      ),
      isNull,
    );
    expect(
      tracker.detect(
        id: 'x',
        at: DateTime.utc(2026, 11, 1, 0),
        settings: settings(overnight: true),
      ),
      isNotNull,
    );
    expect(
      tracker.detect(
        id: 'x',
        at: DateTime.utc(2026, 11, 1, 2),
        settings: settings(overnight: true),
      ),
      isNull,
    );
  });
  test('취소 후 대기 시간을 지키고 새로운 후보를 생성한다', () {
    final cancelled = tracker.cancel(
      candidate(),
      at: at.add(const Duration(seconds: 20)),
    );
    expect(
      tracker.cancel(cancelled, at: at.add(const Duration(seconds: 30))),
      same(cancelled),
    );
    expect(
      tracker.detect(
        id: 'next',
        at: at.add(const Duration(minutes: 1)),
        settings: settings(),
        previous: cancelled,
      ),
      isNull,
    );
    expect(
      tracker
          .detect(
            id: 'next',
            at: at.add(const Duration(seconds: 80)),
            settings: settings(),
            previous: cancelled,
          )!
          .id,
      'next',
    );
    expect(
      () => tracker.confirm(cancelled, at: at.add(const Duration(minutes: 2))),
      throwsStateError,
    );
  });
  test('확인은 관측 시각을 기본값으로 사용하고 중복 요청은 같은 기록을 반환한다', () {
    final confirmed = tracker.confirm(
      candidate(),
      at: at.add(const Duration(minutes: 2)),
    );
    expect(confirmed.wakeAt, at);
    expect(
      tracker.confirm(confirmed, at: at.add(const Duration(minutes: 3))),
      same(confirmed),
    );
    expect(() => tracker.cancel(confirmed, at: at), throwsStateError);
    expect(
      tracker.detect(
        id: 'next',
        at: at.add(const Duration(minutes: 4)),
        settings: settings(),
        previous: confirmed,
      ),
      same(confirmed),
    );
  });
  test('과거·미래 입력을 검증하고 수동 기상은 감지 구간 밖에서도 보완한다', () {
    expect(
      tracker.detect(
        id: 'old',
        at: at.subtract(const Duration(seconds: 1)),
        settings: settings(),
        previous: candidate(),
      ),
      isNull,
    );
    expect(
      () => tracker.confirm(
        candidate(),
        at: at.subtract(const Duration(seconds: 1)),
      ),
      throwsArgumentError,
    );
    expect(
      () => tracker.recordManual(
        id: 'm',
        wakeAt: at.add(const Duration(minutes: 1)),
        recordedAt: at,
      ),
      throwsArgumentError,
    );
    final manual = tracker.recordManual(
      id: 'm',
      wakeAt: at.subtract(const Duration(hours: 2)),
      recordedAt: at,
    );
    expect(manual.source, WakeSource.manual);
    expect(manual.status, WakeStatus.confirmed);
  });
}
