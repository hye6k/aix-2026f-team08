import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _pages = [
    (
      icon: Icons.wb_twilight_outlined,
      title: '나에게 맞는 아침을 준비해요',
      description: '목표 도착 시각에서 출발, 기상, 취침 시각을 함께 계획할 공간이에요.',
    ),
    (
      icon: Icons.checklist_rounded,
      title: '하루를 시작하는 나만의 순서',
      description: '준비 단계와 소요 시간을 정하고, 아침 루틴을 진행할 공간이에요.',
    ),
    (
      icon: Icons.history_rounded,
      title: '아침의 흐름을 돌아봐요',
      description: '확인한 기상 시각과 루틴 실행 기록을 모아 볼 공간이에요.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final page = _pages[_selectedIndex];
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('수면과 아침 루틴')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(page.icon, size: 64, color: colors.primary),
                  const SizedBox(height: 24),
                  Text(
                    page.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(page.description, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  const Text('기능을 준비하고 있어요.'),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_twilight_outlined),
            label: '계획',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rounded),
            label: '루틴',
          ),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: '기록'),
        ],
      ),
    );
  }
}
