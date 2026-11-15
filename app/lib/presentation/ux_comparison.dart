import 'package:flutter/material.dart';

abstract final class _Colors {
  static const background = Color(0xfff8f5ee);
  static const surface = Color(0xfffffdf8);
  static const forest = Color(0xff214d41);
  static const text = Color(0xff20352e);
  static const muted = Color(0xff596e65);
  static const peach = Color(0xfff5dfd2);
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
              '기존 앱은 실제 저장소를 사용합니다. 새 시안의 입력은 임시 데이터이며 저장·알림·감지를 실행하지 않습니다.',
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
  _Place(this.id, this.name, this.location);
  final int id;
  final String name;
  final String location;
}

class _Routine {
  _Routine(
    this.id,
    this.name,
    this.origin,
    this.destination,
    this.deadline,
    this.days,
  );
  final int id;
  final String name;
  final int origin;
  final int destination;
  final TimeOfDay deadline;
  final Set<int> days;
}

const _days = ['월', '화', '수', '목', '금', '토', '일'];
String _dayText(Set<int> days) => [
  for (var i = 1; i <= 7; i++)
    if (days.contains(i)) _days[i - 1],
].join(' · ');

/// 앱 데이터와 무관한 임시 메모리 기반의 UX 시안이다.
class MorningConceptScreen extends StatefulWidget {
  const MorningConceptScreen({super.key, this.today});
  final int? today;
  @override
  State<MorningConceptScreen> createState() => _MorningConceptScreenState();
}

class _MorningConceptScreenState extends State<MorningConceptScreen> {
  final _places = <_Place>[];
  final _routines = <_Routine>[];
  int _nextId = 0;
  int _tab = 0;
  bool _started = false;
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
    setState(() {
      final index = _places.indexWhere((p) => p.id == result.id);
      if (index < 0) {
        _places.add(result);
      } else {
        _places[index] = result;
      }
    });
  }

  Future<void> _routineEditor([_Routine? existing]) async {
    final result = await Navigator.of(context).push<_Routine>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: _conceptTheme(),
          child: _RoutineEditor(
            existing: existing,
            id: existing?.id ?? _nextId++,
            places: _places,
            routines: _routines,
            addPlace: _placeEditor,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = _routines.indexWhere((r) => r.id == result.id);
      if (index < 0) {
        _routines.add(result);
      } else {
        _routines[index] = result;
      }
      _tab = 2;
    });
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

  Widget _today() {
    final today = widget.today ?? DateTime.now().weekday;
    final active = _routines.where((r) => r.days.contains(today)).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '오늘의 아침',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          '${_days[today - 1]}요일에 적용되는 루틴',
          style: const TextStyle(color: _Colors.muted),
        ),
        const SizedBox(height: 22),
        if (active == null)
          _card('오늘 적용된 루틴이 없어요', [
            const Text(
              '관리에서 아침 루틴을 만들고 요일을 선택해 보세요.',
              style: TextStyle(height: 1.5),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _tab = 2),
                child: const Text('루틴 관리하기'),
              ),
            ),
          ])
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
                Text(
                  '오늘의 루틴 · ${active.name}',
                  style: const TextStyle(color: Color(0xffc2dccd)),
                ),
                const SizedBox(height: 14),
                Text(
                  '${_placeName(active.origin)} → ${_placeName(active.destination)}',
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
          _card('아직 예측할 기록이 없어요', const [
            Text(
              '수면·기상·이동 기록이 쌓이면 필요한 시간을 안내할 수 있어요.',
              style: TextStyle(height: 1.5),
            ),
          ]),
          _card('감지와 알림', const [
            Text(
              '시안에서는 실제 이벤트를 수집하거나 알림을 예약하지 않아요.',
              style: TextStyle(height: 1.5),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _records() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '나의 아침 기록',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 22),
      _card('아직 기록이 없어요', const [
        Text(
          '수면 → 기상 → 출발 → 도착으로 이어진 사이클이 이곳에 표시될 예정이에요.',
          style: TextStyle(height: 1.5),
        ),
      ]),
      _card('기록 예시', const [
        Text('예시 · 출근', style: TextStyle(color: _Colors.muted)),
        SizedBox(height: 12),
        Text('수면 구간   23:30 → 07:35'),
        SizedBox(height: 8),
        Text('준비 시간   50분'),
        SizedBox(height: 8),
        Text('이동 시간   35분'),
        SizedBox(height: 12),
        Text(
          '가상 데이터이며 실제 수면 측정 결과가 아니에요.',
          style: TextStyle(color: _Colors.muted, fontSize: 12),
        ),
      ]),
    ],
  );

  Widget _manage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '아침 관리',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        '장소를 저장하고 요일별 아침 루틴을 만들어 보세요.',
        style: TextStyle(color: _Colors.muted),
      ),
      const SizedBox(height: 22),
      _card('내 장소', [
        if (_places.isEmpty) const Text('아직 추가한 장소가 없어요.'),
        for (final p in _places)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(p.name),
            subtitle: Text(p.location),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _placeEditor(p),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _placeEditor,
          icon: const Icon(Icons.add),
          label: const Text('장소 추가'),
        ),
      ]),
      _card('아침 루틴', [
        if (_routines.isEmpty) const Text('만들어진 아침 루틴이 없어요.'),
        for (final r in _routines)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.wb_twilight_outlined),
            title: Text(r.name),
            subtitle: Text(
              '${_placeName(r.origin)} → ${_placeName(r.destination)}\n${r.deadline.format(context)} · ${_dayText(r.days)}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _routineEditor(r),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _routineEditor,
          icon: const Icon(Icons.add),
          label: const Text('아침 루틴 만들기'),
        ),
      ]),
    ],
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: _conceptTheme(),
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: _Colors.background,
        title: const Text('새 UX 시안'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _Colors.peach,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '시안 · 입력은 임시로만 유지되며 실제 감지·알림 없음',
                    style: TextStyle(fontSize: 12, color: Color(0xff704637)),
                  ),
                ),
                const SizedBox(height: 22),
                if (!_started)
                  _intro()
                else if (_tab == 0)
                  _today()
                else if (_tab == 1)
                  _records()
                else
                  _manage(),
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
                  label: '오늘',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: '기록',
                ),
                NavigationDestination(icon: Icon(Icons.tune), label: '관리'),
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
  late final TextEditingController location = TextEditingController(
    text: widget.existing?.location,
  );
  String? error;
  @override
  void dispose() {
    name.dispose();
    location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.existing == null ? '장소 추가' : '장소 수정')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '자주 사용하는 장소',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text('집이나 회사처럼 알아보기 쉬운 이름을 붙여 주세요.'),
          const SizedBox(height: 24),
          TextField(
            controller: name,
            decoration: const InputDecoration(
              labelText: '장소 이름',
              hintText: '예: 집',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: location,
            decoration: const InputDecoration(
              labelText: '위치 설명 또는 주소',
              hintText: '예: 서울시 ...',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '시안에서는 입력한 글자만 임시로 보관해요. 지도·주소 검색과 좌표 저장은 연결되지 않았어요.',
            style: TextStyle(color: _Colors.muted),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || location.text.trim().isEmpty) {
                setState(() => error = '장소 이름과 위치를 입력해 주세요.');
                return;
              }
              Navigator.pop(
                context,
                _Place(widget.id, name.text.trim(), location.text.trim()),
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
  });
  final int id;
  final List<_Place> places;
  final List<_Routine> routines;
  final Future<void> Function() addPlace;
  final _Routine? existing;
  @override
  State<_RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<_RoutineEditor> {
  late final TextEditingController name = TextEditingController(
    text: widget.existing?.name,
  );
  late int? origin = widget.existing?.origin;
  late int? destination = widget.existing?.destination;
  late TimeOfDay deadline =
      widget.existing?.deadline ?? const TimeOfDay(hour: 9, minute: 0);
  late Set<int> days = {...?widget.existing?.days};
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = <int, String>{
      for (final routine in widget.routines.where((r) => r.id != widget.id))
        for (final day in routine.days) day: routine.name,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '아침 루틴 만들기' : '아침 루틴 수정'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
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
            DropdownButtonFormField<int>(
              initialValue: origin,
              decoration: const InputDecoration(labelText: '출발지'),
              items: [
                for (final p in widget.places)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (value) => setState(() => origin = value),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: destination,
              decoration: const InputDecoration(labelText: '도착지'),
              items: [
                for (final p in widget.places)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (value) => setState(() => destination = value),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await widget.addPlace();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('새 장소 추가'),
              ),
            ),
            const SizedBox(height: 16),
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
                    destination == null ||
                    days.isEmpty) {
                  setState(() => error = '이름, 출발지, 도착지와 적용 요일을 모두 선택해 주세요.');
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
                  ),
                );
              },
              child: const Text('루틴 저장'),
            ),
          ],
        ),
      ),
    );
  }
}
