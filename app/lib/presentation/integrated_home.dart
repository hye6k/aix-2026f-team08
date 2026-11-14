import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/morning_runtime.dart';
import '../application/morning_session.dart';
import '../application/session_routine_store.dart';
import '../domain/models.dart';
import '../domain/ports.dart';
import 'routine_screen.dart';
import 'settings_screen.dart';

/// 병합된 설정·루틴 화면과 세션의 계획·기상·실행을 연결한다.
class IntegratedHomeScreen extends StatefulWidget {
  const IntegratedHomeScreen({
    required this.runtime,
    required this.store,
    super.key,
  });
  final MorningRuntime runtime;
  final SessionRoutineStore store;
  @override
  State<IntegratedHomeScreen> createState() => _IntegratedHomeScreenState();
}

class _IntegratedHomeScreenState extends State<IntegratedHomeScreen> {
  late final SessionRoutineStore _store;
  late final StreamSubscription<SessionView> _subscription;
  int _tab = 0;
  bool _busy = false;
  bool _loading = true;
  String? _loadError;
  String? _notice;
  AppSettings? _settings;
  List<Routine> _routines = [];
  List<RoutineRun> _runs = [];
  List<WakeRecord> _wakes = [];
  String? _selectedId;
  late DateTime _day;
  MorningSession get session => widget.runtime.session;

  @override
  void initState() {
    super.initState();
    _day = DateUtils.dateOnly(session.clock());
    _store = widget.store;
    _subscription = session.changes.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_reload());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final settings = await _store.loadSettings();
      final routines = await _store.listRoutines();
      final runs = await _store.listRuns();
      final wakes = await _store.listWakeRecords();
      final checkpoint = await session.store.loadSession();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _routines = routines;
        _runs = runs;
        _wakes = wakes;
        if (checkpoint != null &&
            routines.any((r) => r.id == checkpoint.routineId)) {
          _selectedId = checkpoint.routineId;
          _day = DateTime(
            checkpoint.arrivalDay.year,
            checkpoint.arrivalDay.month,
            checkpoint.arrivalDay.day,
          );
        } else if (!routines.any((r) => r.id == _selectedId)) {
          _selectedId = routines.isEmpty ? null : routines.first.id;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '저장된 정보를 불러오지 못했어요.';
        });
      }
    }
  }

  Future<void> _open(Widget page) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page));
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await action();
      await _reload();
      if (mounted) setState(() => _notice = success);
    } catch (error) {
      if (mounted) {
        setState(
          () => _notice = error is StoreActionBlocked
              ? error.message
              : session.view.alarmUpdatePending ||
                    session.view.cancellationPending
              ? '변경 내용은 저장됐지만 알람을 적용하지 못했어요. 권한을 확인하고 다시 시도해 주세요.'
              : '처리하지 못했어요. 입력과 저장 상태를 확인하고 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDay() async {
    final today = DateUtils.dateOnly(session.clock());
    final initial =
        _day.isBefore(today.subtract(const Duration(days: 365))) ||
            _day.isAfter(today.add(const Duration(days: 730)))
        ? today
        : _day;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 730)),
    );
    if (mounted && selected != null) setState(() => _day = selected);
  }

  Future<void> _applyPlan() async {
    final settings = _settings;
    final selected = _routines.where((r) => r.id == _selectedId);
    if (settings == null || selected.length != 1) {
      setState(() => _notice = '시간 설정과 준비 루틴을 먼저 저장해 주세요.');
      return;
    }
    await _act(
      () => session.configure(
        settings: settings,
        routine: selected.single,
        arrivalDay: _day,
      ),
      '계획을 저장했어요. 알람 상태를 확인해 주세요.',
    );
  }

  Future<void> _manualWake() async {
    final now = session.clock();
    final day = await showDatePicker(
      context: context,
      initialDate: DateUtils.dateOnly(now),
      firstDate: DateUtils.dateOnly(now.subtract(const Duration(days: 30))),
      lastDate: DateUtils.dateOnly(now),
    );
    if (!mounted || day == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (!mounted || time == null) return;
    final selected = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    if (selected.isAfter(session.clock())) {
      setState(() => _notice = '현재보다 미래인 시각은 기상 기록으로 입력할 수 없어요.');
      return;
    }
    await _act(() => session.recordManualWake(selected), '입력한 기상 시각을 저장했어요.');
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  String _date(DateTime value) =>
      '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
  String _at(DateTime? value) {
    if (value == null) return '—';
    final d = value.toLocal();
    return '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _wakeState(WakeRecord? w) => switch (w?.status) {
    WakeStatus.pending => '기상 후보 · 확인 전',
    WakeStatus.confirmed => '기상 확인 완료',
    WakeStatus.cancelled => '후보 취소',
    null => '아직 기상 기록이 없어요',
  };
  String _source(WakeSource s) => switch (s) {
    WakeSource.screenOn => '화면 켜짐 신호',
    WakeSource.manual => '직접 입력',
    WakeSource.test => '테스트 입력',
  };
  String _runState(RunStatus s) => switch (s) {
    RunStatus.running => '진행 중',
    RunStatus.completed => '완료',
    RunStatus.stopped => '중단',
  };
  String _stepState(StepStatus s) => switch (s) {
    StepStatus.pending => '대기',
    StepStatus.active => '진행 중',
    StepStatus.completed => '완료',
    StepStatus.skipped => '건너뜀',
    StepStatus.interrupted => '중단',
  };
  Widget _card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
  Widget _line(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text('$name  $value'),
  );
  Widget _action(
    String label,
    Future<void> Function() callback, {
    bool enabled = true,
    String? success,
  }) => OutlinedButton(
    onPressed: _busy || !enabled
        ? null
        : () => _act(callback, success ?? '$label 처리했어요.'),
    child: Text(label),
  );

  Widget _plan(SessionView v) {
    final plan = v.plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card('아침 계획', [
          const Text('목표 도착 시간과 준비 루틴을 바탕으로 출발·기상·취침 시각을 계산해요.'),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () => _open(
                    SettingsScreen(
                      store: _store,
                      openStore: () async => _store,
                    ),
                  ),
            child: const Text('시간 설정'),
          ),
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () => _open(
                    RoutineLibraryScreen(
                      store: _store,
                      openStore: () async => _store,
                    ),
                  ),
            child: const Text('루틴 관리'),
          ),
          if (_settings == null) const Text('시간 설정을 먼저 저장해 주세요.'),
          if (_routines.isEmpty) const Text('준비 루틴을 한 개 이상 등록해 주세요.'),
          if (_routines.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey('routine-${_selectedId ?? ''}'),
              initialValue: _selectedId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '계획에 사용할 루틴'),
              items: [
                for (final r in _routines)
                  DropdownMenuItem(
                    value: r.id,
                    child: Text(r.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _selectedId = value),
            ),
          OutlinedButton(
            onPressed: _busy ? null : _chooseDay,
            child: Text('목표 날짜 선택 · ${_date(_day)}'),
          ),
          FilledButton(
            onPressed: _busy || _settings == null || _selectedId == null
                ? null
                : _applyPlan,
            child: const Text('계획 계산 및 저장'),
          ),
          const Text('날짜별 단발 계획입니다. 다음 날 알람은 새 날짜를 선택해 설정해야 해요.'),
        ]),
        if (plan != null)
          _card('계산 결과', [
            _line('목표 도착', _at(plan.arrivalAt)),
            _line('권장 출발', _at(plan.departureAt)),
            _line('권장 기상', _at(plan.recommendedWakeAt)),
            _line('적용 알람', _at(plan.alarmAt)),
            _line('권장 취침', _at(plan.bedtimeAt)),
            _line('준비 시간', '${plan.preparation.inMinutes}분'),
            if (!plan.alarmAt.isAfter(session.clock()))
              const Text('적용 알람 시각이 지나 새 알람을 예약하지 않았어요.'),
          ]),
        _card('알람 권한', [
          ValueListenableBuilder(
            valueListenable: widget.runtime.permissions,
            builder: (_, permissions, child) => Text(
              '알림: ${permissions?.notifications == true ? '허용' : '미허용 또는 확인 필요'} · 정확한 알람: ${permissions?.exactAlarm == true ? '허용' : '미허용 또는 확인 필요'}',
            ),
          ),
          _action(
            '알림 권한 요청',
            widget.runtime.platform.requestNotificationPermission,
          ),
          _action(
            '정확한 알람 설정 열기',
            widget.runtime.platform.requestExactAlarmPermission,
          ),
          _action('권한 상태 새로고침', widget.runtime.refreshPlatform),
        ]),
      ],
    );
  }

  Widget _progress(SessionView v) {
    final wake = v.wake;
    final prediction = v.prediction;
    final run = v.run;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (v.plan == null)
          _card('계획이 필요해요', [const Text('계획 탭에서 시간과 루틴을 저장한 뒤 진행해 주세요.')]),
        if (prediction != null)
          _card(
            prediction.isConditional
                ? '지금 준비를 시작하면'
                : run?.status == RunStatus.completed
                ? '지금 출발하면'
                : '현재 진행에 따른 예상',
            [
              _line('예상 도착', _at(prediction.arrivalAt)),
              _line('예상 지각', '${prediction.lateMinutes}분'),
              _line(
                '남은 준비',
                '${(prediction.remainingPreparation.inSeconds / 60).ceil()}분',
              ),
              const Text('예상은 입력한 이동 시간 기준이며 실제 교통 상황은 반영하지 않아요.'),
            ],
          ),
        _card('기상 확인', [
          Text(_wakeState(wake)),
          if (wake != null) _line(_source(wake.source), _at(wake.observedAt)),
          if (wake?.wakeAt != null) _line('확인한 기상', _at(wake!.wakeAt)),
          if (wake?.status == WakeStatus.pending) ...[
            _action('일어났어요', session.confirmWake, success: '기상을 확인했어요.'),
            _action('아직이에요', session.cancelCandidate, success: '기상 후보를 취소했어요.'),
          ],
          if (v.plan != null && wake?.status != WakeStatus.confirmed)
            OutlinedButton(
              onPressed: _busy ? null : _manualWake,
              child: const Text('기상 시각 직접 입력'),
            ),
          if (kDebugMode &&
              v.plan != null &&
              wake?.status != WakeStatus.confirmed)
            _action('테스트 기상 신호', () async {
              await session.observe(
                ActivitySignal(at: session.clock(), source: WakeSource.test),
              );
              if (session.view.wake?.status != WakeStatus.pending) {
                throw const StoreActionBlocked(
                  '감지 구간 밖이거나 취소 후 재감지 대기 중이에요. 설정된 시간과 1분 대기를 확인해 주세요.',
                );
              }
            }, success: '테스트 후보를 입력했어요. 실제 화면 감지와 구분됩니다.'),
          const Text('알람 해제와 기상 확인은 별개입니다.'),
        ]),
        _card('루틴 진행', [
          if (run == null) const Text('준비를 시작하면 순서대로 진행할 수 있어요.'),
          if (run != null) _line('상태', _runState(run.status)),
          if (run == null || run.status != RunStatus.running)
            _action('루틴 시작', session.startRoutine, enabled: v.plan != null),
          if (run != null)
            for (final step in run.steps) ...[
              _line(
                step.step.name,
                '${_stepState(step.status)} · 예상 ${step.step.expected.inMinutes}분',
              ),
              if (step.status == StepStatus.active) ...[
                _line(
                  '경과 시간',
                  '${session.clock().isBefore(step.startedAt!) ? 0 : session.clock().difference(step.startedAt!).inMinutes}분',
                ),
                _action('현재 단계 완료', () => session.completeStep(step.step.id)),
                _action('현재 단계 건너뛰기', () => session.skipStep(step.step.id)),
              ],
            ],
          if (run?.status == RunStatus.running)
            _action('루틴 중단', session.stopRoutine),
          const Text('직접 루틴을 시작해도 기상 시각은 자동 확정되지 않아요.'),
        ]),
      ],
    );
  }

  Widget _history() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _card('기상 기록', [
        if (_wakes.isEmpty) const Text('아직 기상 기록이 없어요.'),
        for (final wake in _wakes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_wakeState(wake)),
            subtitle: Text(
              '${_source(wake.source)} · ${_at(wake.wakeAt ?? wake.observedAt)}',
            ),
          ),
      ]),
      _card('루틴 기록', [
        if (_runs.isEmpty) const Text('아직 실행 기록이 없어요.'),
        for (final run in _runs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${run.routineName} · ${_runState(run.status)}'),
            subtitle: Text(
              '${_at(run.startedAt)} · 완료 ${run.steps.where((s) => s.status == StepStatus.completed).length}/${run.steps.length}단계',
            ),
          ),
      ]),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final v = session.view;
    return Scaffold(
      appBar: AppBar(
        title: const Text('수면과 아침 루틴'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _busy
                ? null
                : () {
                    session.refreshClock();
                    unawaited(_reload());
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('다시 불러오기'),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              _notice!,
                              key: const Key('integration-notice'),
                            ),
                          ),
                        ValueListenableBuilder(
                          valueListenable: widget.runtime.platformError,
                          builder: (_, error, child) => error == null
                              ? const SizedBox.shrink()
                              : const Text('Android 알람 또는 알림 동작을 확인해 주세요.'),
                        ),
                        if (v.alarmUpdatePending || v.cancellationPending)
                          _card('알람 적용 확인 필요', [
                            const Text(
                              '계획이나 기상은 저장됐지만 알람 적용이 완료되지 않았어요. 권한 확인 후 다시 시도해 주세요.',
                            ),
                            _action('알람 적용 다시 시도', session.retryAlarm),
                          ]),
                        if (_tab == 0)
                          _plan(v)
                        else if (_tab == 1)
                          _progress(v)
                        else
                          _history(),
                      ],
                    ),
                  ),
                ),
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() {
            _tab = i;
            _notice = null;
          });
          if (i == 2) unawaited(_reload());
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_twilight_outlined),
            label: '계획',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rounded),
            label: '진행',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: '기록'),
        ],
      ),
    );
  }
}
