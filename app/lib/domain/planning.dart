import 'models.dart';

DailyPlan calculateDailyPlan({
  required DateTime arrivalDay,
  required AppSettings settings,
  required Routine routine,
}) {
  final arrival = settings.arrivalTime.on(arrivalDay);
  final departure = arrival.subtract(settings.travelDuration);
  final recommended = departure.subtract(routine.expected);
  // 수동 시각의 날짜는 권장 기상 날짜를 사용한다. 늦은 수동 시각도 보존한다.
  final alarm = settings.wakeMode == WakeMode.manual
      ? settings.manualWakeTime!.on(recommended)
      : recommended;
  return DailyPlan(
    arrivalAt: arrival,
    departureAt: departure,
    recommendedWakeAt: recommended,
    alarmAt: alarm,
    bedtimeAt: alarm.subtract(settings.sleepDuration),
    preparation: routine.expected,
  );
}
