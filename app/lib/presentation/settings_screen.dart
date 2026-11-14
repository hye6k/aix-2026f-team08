import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/ports.dart';
import 'confirmation_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.store, required this.openStore});
  final RoutineStore? store;
  final Future<RoutineStore> Function() openStore;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  final _travelHours = TextEditingController();
  final _travelMinutes = TextEditingController();
  final _sleepHours = TextEditingController();
  final _sleepMinutes = TextEditingController();
  RoutineStore? _store;
  bool _loading = false;
  bool _saving = false;
  bool _existing = false;
  String? _loadError;
  String? _saveError;
  WakeMode _mode = WakeMode.recommended;
  final Map<String, ClockTime?> _times = {};
  final Map<String, GlobalKey<FormFieldState<ClockTime>>> _timeKeys = {
    for (final id in ['arrival', 'manual', 'start', 'end'])
      id: GlobalKey<FormFieldState<ClockTime>>(),
  };
  final _durationKeys = List.generate(
    4,
    (_) => GlobalKey<FormFieldState<String>>(),
  );
  final Map<TextEditingController, Duration> _originalDurations = {};
  final Set<TextEditingController> _editedDurations = {};
  String? _baseline;
  bool _allowPop = false;
  bool _confirmingExit = false;
  bool _picking = false;

  String _fingerprint() => jsonEncode([
    _mode.name,
    for (final id in ['arrival', 'manual', 'start', 'end']) _times[id]?.minutes,
    _travelHours.text,
    _travelMinutes.text,
    _sleepHours.text,
    _sleepMinutes.text,
    _durationFingerprint(_travelHours, _travelMinutes),
    _durationFingerprint(_sleepHours, _sleepMinutes),
  ]);

  int? _durationFingerprint(
    TextEditingController hours,
    TextEditingController minutes,
  ) {
    if (!_editedDurations.contains(hours) &&
        _originalDurations.containsKey(hours)) {
      return _originalDurations[hours]!.inMicroseconds;
    }
    final h = int.tryParse(hours.text.trim());
    final m = int.tryParse(minutes.text.trim());
    if (h == null || m == null || h < 0 || h > 24 || m < 0 || m > 59) {
      return null;
    }
    return Duration(hours: h, minutes: m).inMicroseconds;
  }

  Future<void> _leave() async {
    if (!mounted || _saving || _confirmingExit || _allowPop) return;
    _confirmingExit = true;
    final discard =
        _baseline == null ||
        _baseline == _fingerprint() ||
        await showConfirmation(
          context: context,
          title: '변경한 내용을 저장하지 않고 나갈까요?',
          message: '저장하지 않은 변경 내용은 사라져요.',
          cancelLabel: '계속 수정',
          confirmLabel: '저장하지 않고 나가기',
        );
    _confirmingExit = false;
    if (!mounted || !discard) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      _store ??= widget.store ?? await widget.openStore();
      if (!mounted) {
        if (widget.store == null) await _store!.close();
        return;
      }
      final settings = await _store!.loadSettings();
      if (!mounted) return;
      if (settings != null) {
        _times.addAll({
          'arrival': settings.arrivalTime,
          'manual': settings.manualWakeTime,
          'start': settings.detectionStart,
          'end': settings.detectionEnd,
        });
        _mode = settings.wakeMode;
        _setDuration(settings.travelDuration, _travelHours, _travelMinutes);
        _setDuration(settings.sleepDuration, _sleepHours, _sleepMinutes);
      }
      setState(() {
        _existing = settings != null;
        _loading = false;
        _baseline = _fingerprint();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '설정을 불러오지 못했어요. 다시 시도해 주세요.';
        });
      }
    }
  }

  void _setDuration(
    Duration value,
    TextEditingController hours,
    TextEditingController minutes,
  ) {
    _originalDurations[hours] = value;
    hours.text = '${value.inHours}';
    minutes.text = '${value.inMinutes % 60}';
  }

  @override
  void dispose() {
    for (final controller in [
      _travelHours,
      _travelMinutes,
      _sleepHours,
      _sleepMinutes,
    ]) {
      controller.dispose();
    }
    if (widget.store == null) _store?.close();
    super.dispose();
  }

  Future<void> _pick(String id, FormFieldState<ClockTime> field) async {
    if (_picking || _saving) return;
    _picking = true;
    final old = _times[id];
    final value = await showTimePicker(
      context: context,
      initialTime: old == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: old.hour, minute: old.minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    _picking = false;
    if (!mounted || value == null || !field.mounted) return;
    setState(() {
      _times[id] = ClockTime(value.hour, value.minute);
      _saveError = null;
    });
    field.didChange(_times[id]);
  }

  Widget _time(String id, String label) => FormField<ClockTime>(
    key: _timeKeys[id],
    initialValue: _times[id],
    validator: (_) {
      if (_times[id] == null) return '$label을 선택해 주세요.';
      if (id == 'end' && _times['start'] == _times['end']) {
        return '감지 시작 시각과 종료 시각을 다르게 선택해 주세요.';
      }
      return null;
    },
    builder: (field) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$label · 필수'),
          const SizedBox(height: 8),
          OutlinedButton(
            key: ValueKey('time-$id'),
            onPressed: _saving ? null : () => _pick(id, field),
            child: Semantics(
              label: '$label 선택',
              child: Text(_times[id]?.toString() ?? '시각 선택'),
            ),
          ),
          if (field.hasError)
            Text(
              field.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );

  Widget _duration(
    String label,
    TextEditingController hours,
    TextEditingController minutes, {
    bool allowZero = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$label · 필수'),
          const SizedBox(height: 8),
          for (final part in [(hours, '시간'), (minutes, '분')])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextFormField(
                key:
                    _durationKeys[(allowZero ? 0 : 2) +
                        (part.$2 == '분' ? 1 : 0)],
                controller: part.$1,
                onChanged: (_) => setState(() {
                  _editedDurations.add(hours);
                }),
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '$label, ${part.$2}',
                  suffixText: part.$2,
                  border: const OutlineInputBorder(),
                ),
                validator: (text) {
                  if (_originalDurations.containsKey(hours) &&
                      !_editedDurations.contains(hours)) {
                    return null;
                  }
                  if (text == null || text.trim().isEmpty) {
                    return '$label의 시간과 분을 모두 입력해 주세요.';
                  }
                  if (!RegExp(r'^\d+$').hasMatch(text.trim())) {
                    return '0 이상의 정수를 입력해 주세요.';
                  }
                  final value = int.tryParse(text.trim());
                  if (value == null) {
                    return '입력한 값이 너무 커요.';
                  }
                  if (part.$2 == '분' && value > 59) {
                    return '분은 0부터 59까지 입력해 주세요.';
                  }
                  final h = int.tryParse(hours.text.trim());
                  final m = int.tryParse(minutes.text.trim());
                  if (h != null &&
                      m != null &&
                      (h > 24 ||
                          h * 60 + m > 1440 ||
                          (!allowZero && h * 60 + m == 0))) {
                    return allowZero
                        ? '이동 시간은 0분부터 24시간까지 입력할 수 있어요.'
                        : '수면 시간은 1분부터 24시간까지 입력해 주세요.';
                  }
                  return null;
                },
              ),
            ),
          if (_originalDurations[hours] case final original?
              when original.inMicroseconds % Duration.microsecondsPerMinute !=
                  0)
            Text(
              '기존 $label: ${original.inMicroseconds / Duration.microsecondsPerSecond}초. 시간을 수정하면 분 단위로 적용돼요.',
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) {
      final keys = <GlobalKey<FormFieldState<dynamic>>>[
        _timeKeys['arrival']!,
        ..._durationKeys,
        if (_mode == WakeMode.manual) _timeKeys['manual']!,
        _timeKeys['start']!,
        _timeKeys['end']!,
      ];
      for (final key in keys) {
        if (key.currentState?.hasError == true && key.currentContext != null) {
          await Scrollable.ensureVisible(
            key.currentContext!,
            duration: const Duration(milliseconds: 200),
          );
          break;
        }
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final settings = AppSettings(
        arrivalTime: _times['arrival']!,
        travelDuration:
            !_editedDurations.contains(_travelHours) &&
                _originalDurations.containsKey(_travelHours)
            ? _originalDurations[_travelHours]!
            : Duration(
                hours: int.parse(_travelHours.text.trim()),
                minutes: int.parse(_travelMinutes.text.trim()),
              ),
        sleepDuration:
            !_editedDurations.contains(_sleepHours) &&
                _originalDurations.containsKey(_sleepHours)
            ? _originalDurations[_sleepHours]!
            : Duration(
                hours: int.parse(_sleepHours.text.trim()),
                minutes: int.parse(_sleepMinutes.text.trim()),
              ),
        wakeMode: _mode,
        manualWakeTime: _times['manual'],
        detectionStart: _times['start']!,
        detectionEnd: _times['end']!,
      );
      await _store!.saveSettings(settings);
      if (!mounted) return;
      setState(() {
        _existing = true;
        _originalDurations[_travelHours] = settings.travelDuration;
        _originalDurations[_sleepHours] = settings.sleepDuration;
        _editedDurations.clear();
        _baseline = _fingerprint();
      });
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('설정을 저장했어요.')));
    } catch (error) {
      if (mounted) {
        setState(
          () => _saveError = error is StoreActionBlocked
              ? error.message
              : '설정을 저장하지 못했어요. 입력한 내용은 유지돼요. 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('시간 설정'),
        leading: IconButton(
          tooltip: '뒤로',
          onPressed: _saving ? null : _leave,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? '저장 중…'
                      : _saveError != null
                      ? '다시 저장'
                      : '설정 저장',
                ),
              ),
            ),
      body: SafeArea(
        child: _loading
            ? SingleChildScrollView(
                child: Semantics(
                  liveRegion: true,
                  child: Text('설정을 불러오는 중이에요.'),
                ),
              )
            : _loadError != null
            ? SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('다시 불러오기'),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _existing
                                ? '저장된 설정을 수정할 수 있어요.'
                                : '목표 도착 시각과 수면·기상 시간을 설정해 주세요.',
                          ),
                          _heading('도착 계획'),
                          _time('arrival', '목표 도착 시각'),
                          _duration(
                            '이동 시간',
                            _travelHours,
                            _travelMinutes,
                            allowZero: true,
                          ),
                          const Text(
                            '목적지까지 이동하는 데 걸리는 시간이에요. 이동이 필요 없으면 0분을 입력해 주세요.',
                          ),
                          _heading('수면·기상 계획'),
                          _duration('수면 시간', _sleepHours, _sleepMinutes),
                          const Text(
                            '계획에 사용할 수면 시간을 입력해 주세요. 기상 알람 시각에서 이 시간을 빼 취침 시각을 계산해요.',
                          ),
                          const Text('실제 수면 시간을 측정하는 기능은 아니에요.'),
                          const SizedBox(height: 16),
                          const Text('기상 시각 설정'),
                          RadioGroup<WakeMode>(
                            groupValue: _mode,
                            onChanged: (value) {
                              if (!_saving && value != null) {
                                setState(() => _mode = value);
                              }
                            },
                            child: Column(
                              children: [
                                RadioListTile<WakeMode>(
                                  enabled: !_saving,
                                  value: WakeMode.recommended,
                                  title: const Text('권장 시각 사용'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                                RadioListTile<WakeMode>(
                                  enabled: !_saving,
                                  value: WakeMode.manual,
                                  title: const Text('직접 지정'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            '권장 시각은 목표 도착 시각, 이동 시간, 루틴의 준비 시간을 바탕으로 계산해요. 직접 지정하면 입력한 시각을 기상 알람에 사용해요.',
                          ),
                          if (_mode == WakeMode.manual) ...[
                            _time('manual', '직접 지정할 기상 시각'),
                            const Text(
                              '앞으로 일어날 시각을 지정해 주세요. 실제로 일어난 시각을 기록하는 항목은 아니에요.',
                            ),
                          ],
                          _heading('기상 감지 시간'),
                          const Text(
                            '이 시간대에 활동 신호가 감지되면 기상 확인을 요청해요. 실제 기상 여부는 직접 확인해 주세요.',
                          ),
                          _time('start', '감지 시작 시각'),
                          _time('end', '감지 종료 시각'),
                          const Text('시작 시각부터 감지하고, 종료 시각부터는 감지하지 않아요.'),
                          if (_times['start'] != null &&
                              _times['end'] != null &&
                              _times['start']!.minutes > _times['end']!.minutes)
                            Text(
                              '감지 시간: ${_times['start']}~다음 날 ${_times['end']}\n종료 시각이 시작 시각보다 이르면 다음 날까지 이어져요.',
                            ),
                          const SizedBox(height: 24),
                          if (_saveError != null)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _saveError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
