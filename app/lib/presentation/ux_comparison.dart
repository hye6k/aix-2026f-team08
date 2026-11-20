import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'location_picker.dart';

abstract final class _Colors {
  static const background = Color(0xfff8f5ee);
  static const surface = Color(0xfffffdf8);
  static const forest = Color(0xff214d41);
  static const text = Color(0xff20352e);
  static const muted = Color(0xff596e65);
  static const outline = Color(0xffe8e6da);
}

ThemeData _conceptTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _Colors.forest).copyWith(
    primary: _Colors.forest,
    onPrimary: Colors.white,
    surface: _Colors.surface,
    onSurface: _Colors.text,
  ),
  scaffoldBackgroundColor: _Colors.background,
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: _Colors.surface,
    indicatorColor: Color(0xffdcebe1),
  ),
  useMaterial3: true,
  splashFactory: InkRipple.splashFactory,
);

/// 명시적으로 켠 디버그 빌드에서만 기존 앱과 시안을 선택한다.
class UxComparisonScreen extends StatelessWidget {
  const UxComparisonScreen({required this.existing, super.key});
  final Widget existing;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('화면 비교')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '두 가지 흐름을 비교해 보세요',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              '기존 앱과 새 시안은 별도 데이터를 사용합니다. 새 시안의 자동 감지와 알림은 아직 동작하지 않습니다.',
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MorningConceptScreen(),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('새 UX 시안 보기'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => existing)),
              icon: const Icon(Icons.phone_android_outlined),
              label: const Text('기존 앱 보기'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Place {
  _Place(this.id, this.name, this.location, {this.latitude, this.longitude});
  final int id;
  final String name;
  final String location;
  final double? latitude;
  final double? longitude;
}

class _Routine {
  _Routine(
    this.id,
    this.name,
    this.origin,
    this.destination,
    this.deadline,
    this.days, {
    this.wake,
  });
  final int id;
  final String name;
  final int origin;
  final int destination;
  final TimeOfDay deadline;
  final Set<int> days;
  final TimeOfDay? wake;
}

class _MockRecord {
  const _MockRecord(
    this.routine,
    this.sleep,
    this.wake,
    this.departure,
    this.arrival,
  );
  final _Routine routine;
  final DateTime sleep;
  final DateTime wake;
  final DateTime departure;
  final DateTime arrival;
}

const _days = ['월', '화', '수', '목', '금', '토', '일'];
String _dayText(Set<int> days) => [
  for (var i = 1; i <= 7; i++)
    if (days.contains(i)) _days[i - 1],
].join(' · ');

/// 앱 제품 저장소와 분리된 UX 시안이다.
class MorningConceptScreen extends StatefulWidget {
  const MorningConceptScreen({
    super.key,
    this.now,
    this.persist = true,
    this.existing,
    this.developerOptions = false,
  });
  final DateTime? now;
  final bool persist;
  final Widget? existing;
  final bool developerOptions;
  @override
  State<MorningConceptScreen> createState() => _MorningConceptScreenState();
}

class _MorningConceptScreenState extends State<MorningConceptScreen>
    with WidgetsBindingObserver {
  final _places = <_Place>[];
  final _routines = <_Routine>[];
  int _nextId = 0;
  int _tab = 0;
  bool _started = false;
  bool _loading = true;
  bool _saving = false;
  String? _storageError;
  Timer? _clockTimer;
  bool _mockActive = false;
  String? _recordMonth;
  String _mockTodayStatus = 'pending';
  List<_Place>? _originalPlaces;
  List<_Routine>? _originalRoutines;
  int? _originalNextId;
  late final Future<SharedPreferences> _preferences =
      SharedPreferences.getInstance();

  static const _platform = MethodChannel('morning_routine/platform');
  static const _summaryPreference = 'ux_routine_summary_enabled';
  bool _summaryEnabled = false;
  bool _summaryReady = false;

  Future<void> _syncRoutineSummary({bool readLaunch = false}) async {
    if (!_summaryReady || !Platform.isAndroid) return;
    try {
      if (readLaunch &&
          await _platform.invokeMethod<bool>('takeRoutineSummaryLaunch') ==
              true &&
          mounted) {
        setState(() => _tab = 0);
      }
      final now = DateTime.now();
      final (routine, day) = _homeRoutine(now, useMock: false);
      if (!_summaryEnabled || routine == null) {
        await _platform.invokeMethod<void>('clearRoutineSummary');
        return;
      }
      String time(TimeOfDay value) =>
          '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
      final places = _mockActive ? _originalPlaces! : _places;
      final destination = places
          .where((place) => place.id == routine.destination)
          .firstOrNull;
      final wake = routine.wake;
      await _platform.invokeMethod<void>('showRoutineSummary', {
        'title': routine.name,
        'body':
            '${day.month}/${day.day} · ${destination?.name ?? "도착지"} '
            '${time(routine.deadline)}까지${wake == null ? "" : " · 기상 ${time(wake)}"}',
        'expiresAt': DateTime(
          day.year,
          day.month,
          day.day + 1,
        ).millisecondsSinceEpoch,
      });
    } on PlatformException {
      // The home card remains available if the system cannot post the summary.
    } on MissingPluginException {
      // This host does not provide Android notifications.
    }
  }

  Future<void> _setRoutineSummary(bool enabled) async {
    try {
      if (!await (await _preferences).setBool(_summaryPreference, enabled) ||
          !mounted) {
        return;
      }
      setState(() => _summaryEnabled = enabled);
      if (enabled && Platform.isAndroid) {
        await _platform.invokeMethod<void>('requestNotificationPermission');
      }
      await _syncRoutineSummary();
    } on PlatformException {
      // The switch can be changed again after resolving the platform issue.
    } on MissingPluginException {
      // This host does not provide Android notifications.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.now == null) {
      _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      unawaited(_syncRoutineSummary(readLaunch: true));
    } else if (state == AppLifecycleState.paused) {
      unawaited(_syncRoutineSummary());
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = widget.persist
          ? (await _preferences).getString('ux_location_draft_v1')
          : null;
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final places = (data['places'] as List)
            .map(
              (e) => _Place(
                e['id'] as int,
                e['name'] as String,
                e['location'] as String,
                latitude: (e['lat'] as num?)?.toDouble(),
                longitude: (e['lng'] as num?)?.toDouble(),
              ),
            )
            .toList();
        final routines = (data['routines'] as List)
            .map(
              (e) => _Routine(
                e['id'] as int,
                e['name'] as String,
                e['origin'] as int,
                e['destination'] as int,
                TimeOfDay(hour: e['hour'] as int, minute: e['minute'] as int),
                (e['days'] as List).cast<int>().toSet(),
                wake: e['wakeHour'] == null
                    ? null
                    : TimeOfDay(
                        hour: e['wakeHour'] as int,
                        minute: e['wakeMinute'] as int,
                      ),
              ),
            )
            .toList();
        _places.addAll(places);
        _routines.addAll(routines);
        _nextId = data['nextId'] as int;
        _started = true;
      }
    } catch (_) {
      _storageError = '저장된 시안 데이터를 불러오지 못했어요. 다시 실행해 주세요.';
    }
    if (!mounted) return;
    if (widget.persist && Platform.isAndroid) {
      _summaryEnabled =
          (await _preferences).getBool(_summaryPreference) ?? false;
      _summaryReady = true;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    unawaited(_syncRoutineSummary(readLaunch: true));
  }

  Future<bool> _save(List<_Place> places, List<_Routine> routines) async {
    if (!widget.persist || _mockActive) return true;
    if (_saving) return false;
    _saving = true;
    try {
      final saved = await (await _preferences).setString(
        'ux_location_draft_v1',
        jsonEncode({
          'nextId': _nextId,
          'places': [
            for (final p in places)
              {
                'id': p.id,
                'name': p.name,
                'location': p.location,
                'lat': p.latitude,
                'lng': p.longitude,
              },
          ],
          'routines': [
            for (final r in routines)
              {
                'id': r.id,
                'name': r.name,
                'origin': r.origin,
                'destination': r.destination,
                'hour': r.deadline.hour,
                'minute': r.deadline.minute,
                'days': r.days.toList(),
                'wakeHour': r.wake?.hour,
                'wakeMinute': r.wake?.minute,
              },
          ],
        }),
      );
      if (!saved) throw StateError('저장 실패');
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('저장하지 못했어요. 다시 시도해 주세요.')));
      }
      return false;
    } finally {
      _saving = false;
    }
  }

  String _placeName(int id) =>
      _places.where((p) => p.id == id).firstOrNull?.name ?? '알 수 없는 장소';

  Future<void> _placeEditor([_Place? existing]) async {
    final result = await Navigator.of(context).push<_Place>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: _conceptTheme(),
          child: _PlaceEditor(
            existing: existing,
            id: existing?.id ?? _nextId++,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final updated = [..._places];
    final found = updated.indexWhere((p) => p.id == result.id);
    if (found < 0) {
      updated.add(result);
    } else {
      updated[found] = result;
    }
    if (!await _save(updated, _routines) || !mounted) return;
    setState(() {
      final index = _places.indexWhere((p) => p.id == result.id);
      if (index < 0) {
        _places.add(result);
      } else {
        _places[index] = result;
      }
    });
    unawaited(_syncRoutineSummary());
  }

  Future<void> _routineEditor({
    _Routine? existing,
    bool schedule = false,
  }) async {
    final result = await Navigator.of(context).push<_Routine>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: _conceptTheme(),
          child: _RoutineEditor(
            existing: existing,
            schedule: schedule,
            id: existing?.id ?? _nextId++,
            places: _places,
            routines: _routines,
            addPlace: _placeEditor,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final updated = [..._routines];
    final found = updated.indexWhere((r) => r.id == result.id);
    if (found < 0) {
      updated.add(result);
    } else {
      updated[found] = result;
    }
    if (!await _save(_places, updated) || !mounted) return;
    setState(() {
      final index = _routines.indexWhere((r) => r.id == result.id);
      if (index < 0) {
        _routines.add(result);
      } else {
        _routines[index] = result;
      }
      _tab = 2;
    });
    unawaited(_syncRoutineSummary());
  }

  Widget _card(String title, List<Widget> children, {Widget? action}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _Colors.surface,
          border: Border.all(color: _Colors.outline),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  Widget _intro() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      const Text(
        '나의 아침을\n가볍게 준비해요',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        '자주 가는 장소와 아침 루틴을 한 번 정해두면, 요일에 맞는 흐름을 살펴볼 수 있어요.',
        style: TextStyle(color: _Colors.muted, height: 1.6),
      ),
      const SizedBox(height: 32),
      _card('시작하기 전에', const [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.place_outlined),
          title: Text('자주 사용하는 장소 추가'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.route_outlined),
          title: Text('장소를 조합해 아침 루틴 만들기'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.calendar_month_outlined),
          title: Text('루틴을 적용할 요일 선택'),
        ),
      ]),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () => setState(() {
          _started = true;
          _tab = 2;
        }),
        child: const Text('시작하기'),
      ),
    ],
  );

  _Routine? _routineOn(DateTime day) =>
      _routines.where((r) => r.days.contains(day.weekday)).firstOrNull;

  Future<void> _chooseWake(_Routine routine) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: routine.wake ?? const TimeOfDay(hour: 7, minute: 0),
      builder: (_, child) => Theme(data: _conceptTheme(), child: child!),
    );
    if (selected == null || !mounted) return;
    final updated = [
      for (final r in _routines)
        if (r.id == routine.id)
          _Routine(
            r.id,
            r.name,
            r.origin,
            r.destination,
            r.deadline,
            r.days,
            wake: selected,
          )
        else
          r,
    ];
    if (!await _save(_places, updated) || !mounted) return;
    setState(() {
      _routines
        ..clear()
        ..addAll(updated);
    });
    unawaited(_syncRoutineSummary());
  }

  static const _mockLimit = 20;
  int _mockPlaceCount = 4;
  int _mockRoutineCount = 3;

  void _mockExample({bool rest = false}) {
    if (!_mockActive) {
      _originalPlaces = [..._places];
      _originalRoutines = [..._routines];
      _originalNextId = _nextId;
    }
    final now = widget.now ?? DateTime.now();
    final later = DateTime(now.year, now.month, now.day + 2);
    setState(() {
      _mockActive = true;
      _recordMonth = null;
      _mockTodayStatus = 'pending';
      final places = <_Place>[
        _Place(0, '집', '예시 위치', latitude: 37.5, longitude: 127),
        _Place(1, '학교', '예시 위치', latitude: 37.6, longitude: 127.1),
        _Place(2, '실습실', '예시 위치', latitude: 37.59, longitude: 127.08),
        _Place(3, '카페', '예시 위치', latitude: 37.57, longitude: 127.03),
        for (var i = 0; i < 16; i++)
          _Place(
            i + 4,
            const [
              '도서관',
              '학생회관',
              '체육관',
              '기숙사',
              '스터디룸',
              '연구실',
              '미술관',
              '서점',
              '시청',
              '공연장',
              '수영장',
              '공방',
              '지하철역',
              '버스터미널',
              '공원',
              '봉사센터',
            ][i],
            '예시 위치',
            latitude: 37.51 + i * 0.004,
            longitude: 127.01 + i * 0.005,
          ),
      ].take(_mockPlaceCount).toList();
      final routines = <_Routine>[
        _Routine(
          20,
          '오전 강의',
          0,
          1,
          const TimeOfDay(hour: 9, minute: 0),
          rest ? {later.weekday} : {1, 3, 5},
          wake: const TimeOfDay(hour: 7, minute: 0),
        ),
        _Routine(
          21,
          '전공 실습',
          0,
          2,
          const TimeOfDay(hour: 10, minute: 0),
          rest ? {DateTime(now.year, now.month, now.day + 3).weekday} : {2, 4},
          wake: const TimeOfDay(hour: 7, minute: 0),
        ),
        _Routine(
          22,
          '주말 아르바이트',
          0,
          3,
          const TimeOfDay(hour: 11, minute: 0),
          rest ? {DateTime(now.year, now.month, now.day + 4).weekday} : {6},
          wake: const TimeOfDay(hour: 8, minute: 0),
        ),
        for (var i = 3; i < _mockLimit; i++)
          _Routine(
            20 + i,
            const [
              '도서관 공부',
              '동아리 모임',
              '아침 운동',
              '기숙사 방문',
              '조별 과제',
              '연구 미팅',
              '전시 관람',
              '교재 구매',
              '시청 방문',
              '공연 리허설',
              '수영 강습',
              '공방 수업',
              '지하철 환승',
              '시외버스 탑승',
              '공원 산책',
              '봉사 활동',
              '오후 강의',
            ][i - 3],
            0,
            1 + i % (_mockLimit - 1),
            const TimeOfDay(hour: 9, minute: 0),
            {},
          ),
      ];
      _places
        ..clear()
        ..addAll(places);
      _routines
        ..clear()
        ..addAll([
          if (places.length >= 2)
            for (final routine in routines.take(_mockRoutineCount))
              _Routine(
                routine.id,
                routine.name,
                routine.origin,
                1 + (routine.destination - 1) % (places.length - 1),
                routine.deadline,
                routine.days,
                wake: routine.wake,
              ),
        ]);
      _nextId = _mockLimit * 2;
      _tab = 0;
    });
  }

  void _restoreOriginal() {
    if (!_mockActive) return;
    setState(() {
      _places
        ..clear()
        ..addAll(_originalPlaces!);
      _routines
        ..clear()
        ..addAll(_originalRoutines!);
      _nextId = _originalNextId!;
      _mockActive = false;
      _recordMonth = null;
      _originalPlaces = null;
      _originalRoutines = null;
      _originalNextId = null;
    });
  }

  (_Routine?, DateTime) _homeRoutine(DateTime now, {bool useMock = true}) {
    final routines = !useMock && _mockActive ? _originalRoutines! : _routines;
    _Routine? onDay(DateTime day) =>
        routines.where((r) => r.days.contains(day.weekday)).firstOrNull;
    final today = onDay(now);
    final done = useMock && _mockActive && _mockTodayStatus != 'pending';
    if (today != null && !done) return (today, now);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return (onDay(tomorrow), tomorrow);
  }

  Widget _today() {
    final now = widget.now ?? DateTime.now();
    final (active, day) = _homeRoutine(now);
    final showToday = day.day == now.day;
    final isDone = _mockActive && _mockTodayStatus != 'pending';
    final when = '${showToday ? '오늘' : '내일'} · ${_days[day.weekday - 1]}요일';
    final wake = active?.wake;
    final wakeAt = wake == null
        ? null
        : DateTime(day.year, day.month, day.day, wake.hour, wake.minute);
    final remaining = wakeAt?.difference(now);
    final minutes = remaining == null ? 0 : (remaining.inSeconds / 60).ceil();
    final duration =
        '${minutes ~/ 60 > 0 ? '${minutes ~/ 60}시간 ' : ''}${minutes % 60}분';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '다가오는 아침',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('다음으로 예정된 아침 루틴', style: TextStyle(color: _Colors.muted)),
        const SizedBox(height: 22),
        if (_mockActive)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('예시 데이터 사용 중', style: TextStyle(color: _Colors.muted)),
          ),
        if (active == null)
          _card(
            _routines.isEmpty
                ? '아침 루틴이 없어요'
                : isDone
                ? '내일은 쉬는 날이에요'
                : '오늘과 내일은 쉬는 날이에요',
            [
              Text(
                _routines.isEmpty
                    ? '관리에서 아침 루틴을 만들어 주세요.'
                    : isDone
                    ? '내일 적용되는 루틴이 없어요.'
                    : '오늘과 내일 적용되는 루틴이 없어요.',
                style: const TextStyle(height: 1.5),
              ),
              if (_routines.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _tab = 2),
                    child: const Text('루틴 만들기'),
                  ),
                ),
            ],
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _Colors.forest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(when, style: const TextStyle(color: Color(0xffc2dccd))),
                const SizedBox(height: 14),
                Text(
                  _placeName(active.destination),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 25,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${active.deadline.format(context)}까지 도착',
                  style: const TextStyle(
                    color: Color(0xffd5e6db),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card('기상 시간', [
            Text(
              active.wake == null
                  ? '원하는 기상 시간을 정해 주세요.'
                  : '${active.wake!.format(context)}에 일어나기',
              style: const TextStyle(fontSize: 16),
            ),
            if (remaining != null) ...[
              const SizedBox(height: 8),
              Text(
                remaining.isNegative || remaining == Duration.zero
                    ? '설정한 기상 시각이 지났어요.'
                    : '지금 잠들면 기상 시각까지 $duration 남아요.',
                style: const TextStyle(color: _Colors.muted, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              '기상 알람은 아직 연결되지 않았어요.',
              style: TextStyle(color: _Colors.muted, fontSize: 13),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _chooseWake(active),
                child: Text(active.wake == null ? '기상 시간 정하기' : '기상 시간 변경'),
              ),
            ),
          ]),
        ],
      ],
    );
  }

  List<_MockRecord> _mockRecords() {
    final now = widget.now ?? DateTime.now();
    final records = <_MockRecord>[];
    for (var offset = 1; offset <= 60; offset++) {
      final day = DateTime(now.year, now.month, now.day - offset);
      final routine = _routineOn(day);
      if (routine == null) continue;
      final deadline = DateTime(
        day.year,
        day.month,
        day.day,
        routine.deadline.hour,
        routine.deadline.minute,
      );
      final arrival = deadline.subtract(Duration(minutes: 5 + offset % 8));
      final departure = arrival.subtract(Duration(minutes: 28 + offset % 12));
      final wake = departure.subtract(Duration(minutes: 42 + offset % 18));
      final sleep = wake.subtract(Duration(minutes: 405 + offset % 65));
      records.add(_MockRecord(routine, sleep, wake, departure, arrival));
    }
    return records;
  }

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  String _date(DateTime time) =>
      '${time.year}년 ${time.month}월 ${time.day}일 · ${_days[time.weekday - 1]}요일';
  String _duration(Duration value) => value.inHours > 0
      ? '${value.inHours}시간 ${value.inMinutes % 60}분'
      : '${value.inMinutes}분';

  void _showMockRecord(_MockRecord record) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_date(record.arrival)} · ${record.routine.name}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text('예시 기록', style: TextStyle(color: _Colors.muted)),
              const SizedBox(height: 18),
              Text('수면   ${_date(record.sleep)} ${_time(record.sleep)}'),
              const SizedBox(height: 10),
              Text('기상   ${_time(record.wake)}'),
              const SizedBox(height: 10),
              Text('출발   ${_time(record.departure)}'),
              const SizedBox(height: 10),
              Text('도착   ${_time(record.arrival)}'),
              const SizedBox(height: 16),
              const Text(
                '수면은 시작과 기상 사이의 구간이며, 중간에 깬 시간은 반영하지 않았어요.',
                style: TextStyle(color: _Colors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _records() {
    final records = _mockActive ? _mockRecords() : <_MockRecord>[];
    final months = records
        .map(
          (r) =>
              '${r.arrival.year}.${r.arrival.month.toString().padLeft(2, '0')}',
        )
        .toSet();
    final visible = _recordMonth == null
        ? records
        : records
              .where(
                (r) =>
                    '${r.arrival.year}.${r.arrival.month.toString().padLeft(2, '0')}' ==
                    _recordMonth,
              )
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '나의 아침 기록',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (_mockActive)
          Text(
            '예시 데이터 · 최근 60일 · ${records.length}건',
            style: const TextStyle(color: _Colors.muted),
          ),
        const SizedBox(height: 14),
        if (!_mockActive)
          _card('아직 기록이 없어요', const [
            Text(
              '수면 → 기상 → 출발 → 도착으로 이어진 사이클이 이곳에 표시될 예정이에요.',
              style: TextStyle(height: 1.5),
            ),
          ])
        else if (records.isEmpty)
          _card('예시 기록이 없어요', const [Text('예시 루틴의 적용 요일을 확인해 주세요.')])
        else ...[
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('전체'),
                selected: _recordMonth == null,
                onSelected: (_) => setState(() => _recordMonth = null),
              ),
              for (final month in months)
                ChoiceChip(
                  label: Text(month),
                  selected: _recordMonth == month,
                  onSelected: (_) => setState(() => _recordMonth = month),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '일정이 없는 날은 기록에서 제외했어요.',
              style: TextStyle(color: _Colors.muted, fontSize: 12),
            ),
          ),
          for (final record in visible)
            _card('${_date(record.arrival)} · ${record.routine.name}', [
              Text(
                '수면 구간 ${_duration(record.wake.difference(record.sleep))} · 준비 ${_duration(record.departure.difference(record.wake))} · 이동 ${_duration(record.arrival.difference(record.departure))}',
                style: const TextStyle(height: 1.5),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _showMockRecord(record),
                  child: const Text('자세히 보기'),
                ),
              ),
            ]),
        ],
      ],
    );
  }

  void _openDeveloper() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Theme(
          data: _conceptTheme(),
          child: StatefulBuilder(
            builder: (context, refresh) => Scaffold(
              appBar: AppBar(title: const Text('개발자 옵션')),
              body: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    '예시 데이터',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '선택한 개수만큼 목록 앞에서부터 불러와요. 첫 세 루틴에 예시 일정과 기록이 있고, 나머지는 일정 미설정으로 표시돼요.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Text('장소 $_mockPlaceCount개'),
                  Slider(
                    value: _mockPlaceCount.toDouble(),
                    max: _mockLimit.toDouble(),
                    divisions: _mockLimit,
                    label: '$_mockPlaceCount개',
                    onChanged: (value) => refresh(() {
                      _mockPlaceCount = value.round();
                      if (_mockPlaceCount < 2) _mockRoutineCount = 0;
                    }),
                  ),
                  Text('루틴 $_mockRoutineCount개'),
                  Slider(
                    value: _mockRoutineCount.toDouble(),
                    max: _mockLimit.toDouble(),
                    divisions: _mockLimit,
                    label: '$_mockRoutineCount개',
                    onChanged: _mockPlaceCount < 2
                        ? null
                        : (value) =>
                              refresh(() => _mockRoutineCount = value.round()),
                  ),
                  if (_mockPlaceCount < 2)
                    const Text('루틴을 불러오려면 장소가 2개 이상 필요해요.'),
                  FilledButton(
                    onPressed: () {
                      _mockExample();
                      Navigator.pop(routeContext);
                    },
                    child: const Text('대학생 예시 데이터 불러오기'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      _mockExample(rest: true);
                      Navigator.pop(routeContext);
                    },
                    child: const Text('오늘·내일 휴식 예시 보기'),
                  ),
                  if (_mockActive) ...[
                    const SizedBox(height: 24),
                    const Text(
                      '오늘 루틴 상태 (예시)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in const [
                          ('pending', '미완료'),
                          ('completed', '완료'),
                          ('failed', '실패'),
                        ])
                          ChoiceChip(
                            label: Text(entry.$2),
                            selected: _mockTodayStatus == entry.$1,
                            onSelected: (_) {
                              setState(() => _mockTodayStatus = entry.$1);
                              refresh(() {});
                            },
                          ),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        _restoreOriginal();
                        Navigator.pop(routeContext);
                      },
                      child: const Text('원래 데이터로 돌아가기'),
                    ),
                  ],
                  if (widget.existing != null) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('기존 앱 화면 열기'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => widget.existing!,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _manage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '아침 관리',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _routineEditor,
        icon: const Icon(Icons.add),
        label: const Text('아침 루틴 만들기'),
      ),
      const SizedBox(height: 16),
      _card('아침 루틴', [
        if (_routines.isEmpty) const Text('만들어진 아침 루틴이 없어요.'),
        for (final r in _routines)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.wb_twilight_outlined),
            title: Text(r.name),
            subtitle: Text(
              '${_placeName(r.origin)} → ${_placeName(r.destination)}\n${r.days.isEmpty ? '일정 미설정' : '${r.deadline.format(context)} · ${_dayText(r.days)}'}',
            ),
            isThreeLine: true,
            onTap: () => _routineEditor(existing: r),
            trailing: TextButton(
              onPressed: () => _routineEditor(existing: r, schedule: true),
              child: const Text('일정 설정'),
            ),
          ),
      ]),
    ],
  );

  void _openPlaces() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: _conceptTheme(),
          child: StatefulBuilder(
            builder: (context, refresh) {
              Future<void> edit([_Place? place]) async {
                await _placeEditor(place);
                if (context.mounted) refresh(() {});
              }

              return Scaffold(
                appBar: AppBar(title: const Text('장소 관리')),
                body: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          FilledButton.icon(
                            onPressed: edit,
                            icon: const Icon(Icons.add),
                            label: const Text('장소 추가'),
                          ),
                          const SizedBox(height: 16),
                          if (_places.isEmpty) const Text('아직 추가한 장소가 없어요.'),
                          for (final place in _places)
                            ListTile(
                              leading: const Icon(Icons.place_outlined),
                              title: Text(place.name),
                              subtitle: Text(
                                place.location.isEmpty
                                    ? '주소 확인 불가'
                                    : place.location,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => edit(place),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showPendingSetting(String title, String description) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text('$description\n\n아직 사용할 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _testBedtimeAlert(BuildContext dialogContext) async {
    String? status;
    String message;
    try {
      status = await _platform.invokeMethod<String>('showBedtimePreview');
      message = switch (status) {
        'posted' => '테스트 알림을 보냈어요. 상단 배너나 알림창을 확인해 주세요.',
        'permission_required' => '알림 권한을 허용한 뒤 테스트를 다시 눌러 주세요.',
        'blocked' => 'Android 설정에서 앱 알림과 취침 알림 테스트 채널을 켜 주세요.',
        _ => '테스트 알림을 보내지 못했어요.',
      };
    } on PlatformException {
      message = '테스트 알림을 보내지 못했어요.';
    } on MissingPluginException {
      message = 'Android 앱을 다시 빌드한 뒤 테스트해 주세요.';
    }
    if (!dialogContext.mounted || !mounted) return;
    if (status == 'posted') Navigator.pop(dialogContext);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openNotificationSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('알림'),
          content: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('잠금화면·알림창 루틴 표시'),
            subtitle: const Text('잠금화면에 루틴 이름과 도착지가 표시될 수 있어요.'),
            value: _summaryEnabled,
            onChanged: _summaryReady
                ? (value) async {
                    await _setRoutineSummary(value);
                    if (context.mounted) refresh(() {});
                  }
                : null,
          ),
          actions: [
            if (widget.developerOptions && Platform.isAndroid)
              TextButton(
                onPressed: () => _testBedtimeAlert(dialogContext),
                child: const Text('강조 알림 테스트'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '설정',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 16),
      ListTile(
        leading: const Icon(Icons.place_outlined),
        title: const Text('장소 관리'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openPlaces,
      ),
      ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: const Text('알림'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openNotificationSettings,
      ),
      for (final (icon, title, description) in const [
        (Icons.bedtime_outlined, '수면 목표', '목표 수면 시간을 설정해요.'),
        (Icons.location_searching, '권한 및 감지 상태', '알림과 위치 권한, 자동 감지 상태를 확인해요.'),
      ])
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showPendingSetting(title, description),
        ),
      if (widget.developerOptions)
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('개발자 옵션'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openDeveloper,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: _conceptTheme(),
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              key: ValueKey(_tab),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_storageError != null)
                  Text(_storageError!)
                else if (!_started)
                  _intro()
                else if (_tab == 0)
                  _today()
                else if (_tab == 1)
                  _records()
                else if (_tab == 2)
                  _manage()
                else
                  _settings(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _started
          ? NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.wb_sunny_outlined),
                  label: '홈',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: '기록',
                ),
                NavigationDestination(icon: Icon(Icons.list_alt), label: '관리'),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: '설정',
                ),
              ],
            )
          : null,
    ),
  );
}

class _PlaceEditor extends StatefulWidget {
  const _PlaceEditor({required this.id, this.existing});
  final int id;
  final _Place? existing;
  @override
  State<_PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<_PlaceEditor> {
  late final TextEditingController name = TextEditingController(
    text: widget.existing?.name,
  );
  late String address = widget.existing?.location ?? '';
  String? error;
  double? latitude;
  double? longitude;
  @override
  void initState() {
    super.initState();
    latitude = widget.existing?.latitude;
    longitude = widget.existing?.longitude;
  }

  Future<void> _chooseLocation({required bool current}) async {
    final selected = await Navigator.of(context).push<SelectedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          useCurrentLocation: current,
          initialLatitude: latitude,
          initialLongitude: longitude,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      latitude = selected.latitude;
      longitude = selected.longitude;
      address = selected.address ?? '';
      error = null;
    });
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.existing == null ? '장소 추가' : '장소 수정')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          OutlinedButton.icon(
            onPressed: () => _chooseLocation(current: true),
            icon: const Icon(Icons.my_location),
            label: const Text('현재 위치 사용'),
          ),
          OutlinedButton.icon(
            onPressed: () => _chooseLocation(current: false),
            icon: const Icon(Icons.map_outlined),
            label: const Text('지도에서 선택'),
          ),
          const SizedBox(height: 16),
          const Text('주소'),
          const SizedBox(height: 4),
          InputDecorator(
            isEmpty: address.isEmpty,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: Text(address),
          ),
          if (latitude != null && address.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('주소를 확인할 수 없어요.'),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            decoration: const InputDecoration(
              labelText: '장소 이름',
              hintText: '예: 집',
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if ((latitude == null || longitude == null) && address.isEmpty) {
                setState(() => error = '위치를 선택해 주세요.');
                return;
              }
              if (name.text.trim().isEmpty) {
                setState(() => error = '장소 이름을 입력해 주세요.');
                return;
              }
              Navigator.pop(
                context,
                _Place(
                  widget.id,
                  name.text.trim(),
                  address,
                  latitude: latitude,
                  longitude: longitude,
                ),
              );
            },
            child: const Text('장소 저장'),
          ),
        ],
      ),
    ),
  );
}

class _RoutineEditor extends StatefulWidget {
  const _RoutineEditor({
    required this.id,
    required this.places,
    required this.routines,
    required this.addPlace,
    this.existing,
    required this.schedule,
  });
  final int id;
  final List<_Place> places;
  final List<_Routine> routines;
  final Future<void> Function() addPlace;
  final _Routine? existing;
  final bool schedule;
  @override
  State<_RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<_RoutineEditor> {
  late final TextEditingController name = TextEditingController(
    text: widget.existing?.name,
  );
  late int? origin = widget.existing?.origin;
  late int? destination = widget.existing?.destination;
  late TimeOfDay? wake = widget.existing?.wake;
  late TimeOfDay deadline =
      widget.existing?.deadline ?? const TimeOfDay(hour: 9, minute: 0);
  late Set<int> days = {...?widget.existing?.days};
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _pickPlace({required bool isOrigin}) async {
    final label = isOrigin ? '출발지' : '도착지';
    final current = isOrigin ? origin : destination;
    const addPlace = -1;
    final choice = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _Colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$label 선택',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _Colors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (widget.places.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '저장된 장소가 없어요.',
                      style: TextStyle(color: _Colors.muted),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.places.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: _Colors.outline),
                      itemBuilder: (_, index) {
                        final place = widget.places[index];
                        final selected = place.id == current;
                        final showAddress =
                            place.location.isNotEmpty &&
                            place.location != '예시 위치';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          selected: selected,
                          selectedTileColor: const Color(0xffe4efe8),
                          selectedColor: _Colors.forest,
                          title: Text(
                            place.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: showAddress
                              ? Text(
                                  place.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: _Colors.muted),
                                )
                              : null,
                          trailing: selected ? const Icon(Icons.check) : null,
                          onTap: () => Navigator.pop(sheetContext, place.id),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: _Colors.outline),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, addPlace),
                  icon: const Icon(Icons.add),
                  label: const Text('새 장소 추가'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    var selected = choice;
    if (choice == addPlace) {
      final previousIds = widget.places.map((place) => place.id).toSet();
      await widget.addPlace();
      if (!mounted) return;
      final added = widget.places
          .where((place) => !previousIds.contains(place.id))
          .firstOrNull;
      if (added == null) return;
      selected = added.id;
    }
    setState(() {
      if (isOrigin) {
        origin = selected;
      } else {
        destination = selected;
      }
      error = null;
    });
  }

  Widget _placeField(String label, int? id, {required bool isOrigin}) {
    final place = widget.places.where((place) => place.id == id).firstOrNull;
    return OutlinedButton(
      onPressed: () => _pickPlace(isOrigin: isOrigin),
      child: Row(
        children: [
          Text(label),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              place?.name ?? '선택',
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.expand_more),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = <int, String>{
      for (final routine in widget.routines.where((r) => r.id != widget.id))
        for (final day in routine.days) day: routine.name,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.schedule
              ? '일정 설정'
              : widget.existing == null
              ? '아침 루틴 만들기'
              : '아침 루틴 수정',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!widget.schedule) ...[
              const Text(
                '어떤 아침을 준비할까요?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: '루틴 이름',
                  hintText: '예: 출근',
                ),
              ),
              const SizedBox(height: 20),
              _placeField('출발지', origin, isOrigin: true),
              const SizedBox(height: 8),
              _placeField('도착지', destination, isOrigin: false),
              const SizedBox(height: 16),
            ] else ...[
              Text(widget.existing!.name),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('도착 마감 시각'),
                trailing: TextButton(
                  onPressed: () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime: deadline,
                    );
                    if (value != null && mounted) {
                      setState(() => deadline = value);
                    }
                  },
                  child: Text(deadline.format(context)),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('기상 시각 (선택)'),
                subtitle: const Text('홈에서도 설정할 수 있어요.'),
                trailing: TextButton(
                  onPressed: () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime: wake ?? const TimeOfDay(hour: 7, minute: 0),
                    );
                    if (value != null && mounted) {
                      setState(() => wake = value);
                    }
                  },
                  child: Text(wake?.format(context) ?? '시간 정하기'),
                ),
              ),
              if (wake != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => wake = null),
                    child: const Text('기상 시각 지우기'),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                '어느 요일에 적용할까요?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                '같은 요일에는 하나의 루틴만 적용할 수 있어요.',
                style: TextStyle(color: _Colors.muted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 1; i <= 7; i++)
                    FilterChip(
                      label: Text(_days[i - 1]),
                      selected: days.contains(i),
                      onSelected: (selected) {
                        if (selected && conflicts.containsKey(i)) {
                          setState(
                            () => error =
                                '${_days[i - 1]}요일은 ‘${conflicts[i]}’ 루틴에 적용 중이에요.',
                          );
                          return;
                        }
                        setState(() {
                          if (selected) {
                            days.add(i);
                          } else {
                            days.remove(i);
                          }
                          error = null;
                        });
                      },
                    ),
                ],
              ),
              if (conflicts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  [
                    for (final i in conflicts.keys.toList()..sort())
                      '${_days[i - 1]}: ${conflicts[i]}',
                  ].join(' · '),
                  style: const TextStyle(color: _Colors.muted, fontSize: 12),
                ),
              ],
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty ||
                    origin == null ||
                    destination == null) {
                  setState(() => error = '이름, 출발지, 도착지를 모두 입력해 주세요.');
                  return;
                }
                if (origin == destination) {
                  setState(() => error = '출발지와 도착지는 서로 다르게 선택해 주세요.');
                  return;
                }
                Navigator.pop(
                  context,
                  _Routine(
                    widget.id,
                    name.text.trim(),
                    origin!,
                    destination!,
                    deadline,
                    {...days},
                    wake: wake,
                  ),
                );
              },
              child: Text(widget.schedule ? '일정 저장' : '루틴 저장'),
            ),
          ],
        ),
      ),
    );
  }
}
