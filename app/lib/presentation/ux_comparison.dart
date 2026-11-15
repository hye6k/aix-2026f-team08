import 'package:flutter/material.dart';

abstract final class _ConceptColors {
  static const background = Color(0xfff8f5ee);
  static const surface = Color(0xfffffdf8);
  static const forest = Color(0xff214d41);
  static const text = Color(0xff20352e);
  static const muted = Color(0xff596e65);
  static const peach = Color(0xfff5dfd2);
  static const peachText = Color(0xff704637);
  static const outline = Color(0xffe8e6da);
}

/// 별도 플래그로 빌드한 디버그 APK에서만 접근하는 화면 비교 도구.
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
              '기존 앱은 실제 저장소를 사용합니다. 새 시안은 예시 데이터만 사용하며 설정·알림·감지를 실행하지 않습니다.',
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

/// 연결된 데이터나 OS 동작이 없는 인터랙티브 UX 시안.
class MorningConceptScreen extends StatefulWidget {
  const MorningConceptScreen({super.key});
  @override
  State<MorningConceptScreen> createState() => _MorningConceptScreenState();
}

class _MorningConceptScreenState extends State<MorningConceptScreen> {
  int _tab = 0;
  bool _configured = false;
  final _origin = TextEditingController(text: '집');
  final _destination = TextEditingController(text: '학교');
  TimeOfDay _deadline = const TimeOfDay(hour: 9, minute: 0);

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    super.dispose();
  }

  Widget _section(String title, Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _ConceptColors.surface,
      border: Border.all(color: _ConceptColors.outline),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );

  Widget _row(String title, String value, {IconData? icon}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: _ConceptColors.muted),
          const SizedBox(width: 10),
        ],
        Expanded(child: Text(title)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _setup() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '아침을 함께 준비할게요',
        style: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        '출발지와 도착할 곳, 도착 시간을 정해 주세요.',
        style: TextStyle(color: _ConceptColors.muted, height: 1.5),
      ),
      const SizedBox(height: 24),
      _section(
        '어디서 어디로 이동하나요?',
        Column(
          children: [
            TextField(
              controller: _origin,
              decoration: const InputDecoration(
                labelText: '출발지',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _destination,
              decoration: const InputDecoration(
                labelText: '도착지',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '시안에서는 위치 검색이나 좌표가 저장되지 않아요.',
              style: TextStyle(color: _ConceptColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      _section(
        '언제까지 도착해야 하나요?',
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('도착 마감 시각'),
          trailing: TextButton(
            onPressed: () async {
              final value = await showTimePicker(
                context: context,
                initialTime: _deadline,
              );
              if (value != null && mounted) setState(() => _deadline = value);
            },
            child: Text(_deadline.format(context)),
          ),
        ),
      ),
      FilledButton(
        onPressed: () {
          if (_origin.text.trim().isEmpty || _destination.text.trim().isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('출발지와 도착지를 입력해 주세요.')));
            return;
          }
          setState(() => _configured = true);
        },
        child: const Text('예시 화면 계속 보기'),
      ),
      const SizedBox(height: 14),
      const Text(
        '아직 데이터가 없는 첫날에는 예측 기준을 정해야 해요. 이 화면의 시간은 모두 예시입니다.',
        style: TextStyle(color: _ConceptColors.muted, height: 1.4),
      ),
    ],
  );

  String _beforeDeadline(int minutes) {
    final total = _deadline.hour * 60 + _deadline.minute - minutes;
    final wrapped = total % (24 * 60);
    final time = TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60);
    return '${total < 0 ? '전날 ' : ''}${time.format(context)}';
  }

  Widget _today() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '오늘의 아침',
        style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        '${_destination.text} · ${_deadline.format(context)}까지',
        style: const TextStyle(color: _ConceptColors.muted),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _ConceptColors.forest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '예시 · 평소 기록을 바탕으로',
              style: TextStyle(color: Color(0xffb8d5c9)),
            ),
            const SizedBox(height: 12),
            Text(
              '${_beforeDeadline(35)}에 출발하면\n마감 시각에 도착해요',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '이동 예상 35분 · 예시 값',
              style: TextStyle(color: Color(0xffd5e6db)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _section(
        '아침 안내',
        Column(
          children: [
            _row(
              '기상 권장',
              _beforeDeadline(85),
              icon: Icons.wb_twilight_outlined,
            ),
            _row(
              '출발 권장',
              _beforeDeadline(35),
              icon: Icons.directions_walk_outlined,
            ),
            const Divider(),
            _row('예상 준비 시간', '50분', icon: Icons.schedule),
          ],
        ),
      ),
      _section(
        '감지와 알림',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '실제 감지·알림 기능은 이 시안에 연결되지 않았어요.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _previewAlert,
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('알림 문구 예시 보기'),
            ),
          ],
        ),
      ),
    ],
  );

  void _previewAlert() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('출발할 시간이에요'),
      content: Text(
        '${_beforeDeadline(35)}에 출발하면 ${_deadline.format(context)}까지 도착할 수 있어요.\n\n알림 디자인 예시이며 실제 알림은 예약되지 않았어요.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );

  Widget _records() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '나의 아침 기록',
        style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        '아래는 화면을 살펴보기 위한 예시예요.',
        style: TextStyle(color: _ConceptColors.muted),
      ),
      const SizedBox(height: 22),
      _section(
        '11월 15일 · 예시',
        Column(
          children: [
            _row('수면', '23:30 → 07:35', icon: Icons.bedtime_outlined),
            _row('기상 후 준비', '50분', icon: Icons.wb_sunny_outlined),
            _row('출발 → 도착', '35분', icon: Icons.near_me_outlined),
          ],
        ),
      ),
      _section(
        '기록에 대해',
        const Text(
          '수면·기상·출발·도착 이벤트와 누락된 기록 보완 방식은 앞으로 검토할 내용이에요. 실제 기록은 사용하지 않습니다.',
          style: TextStyle(height: 1.5),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _ConceptColors.forest)
          .copyWith(
            primary: _ConceptColors.forest,
            onPrimary: Colors.white,
            surface: _ConceptColors.surface,
            onSurface: _ConceptColors.text,
            primaryContainer: const Color(0xffdcebe1),
            onPrimaryContainer: _ConceptColors.forest,
          ),
      scaffoldBackgroundColor: _ConceptColors.background,
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: _ConceptColors.surface,
        indicatorColor: Color(0xffdcebe1),
      ),
      useMaterial3: true,
      splashFactory: InkRipple.splashFactory,
    ),
    child: Scaffold(
      backgroundColor: _ConceptColors.background,
      appBar: AppBar(
        backgroundColor: _ConceptColors.background,
        title: const Text('새 UX 시안'),
        actions: [
          if (_configured)
            TextButton(
              onPressed: () => setState(() {
                _configured = false;
                _tab = 0;
              }),
              child: const Text('설정 다시 보기'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _ConceptColors.peach,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '시안 · 모든 내용은 예시이며 저장·실제 알림 없음',
                    style: TextStyle(
                      fontSize: 12,
                      color: _ConceptColors.peachText,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                if (!_configured)
                  _setup()
                else if (_tab == 0)
                  _today()
                else
                  _records(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _configured
          ? NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (value) => setState(() => _tab = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.wb_sunny_outlined),
                  label: '오늘',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: '기록',
                ),
              ],
            )
          : null,
    ),
  );
}
