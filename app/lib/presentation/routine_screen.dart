import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/ports.dart';
import 'confirmation_dialog.dart';

String _newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String _durationText(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final micros = duration.inMicroseconds % Duration.microsecondsPerSecond;
  return [
    if (hours > 0) '$hours시간',
    if (minutes > 0) '$minutes분',
    if (seconds > 0 || micros > 0)
      '${seconds + micros / Duration.microsecondsPerSecond}초',
    if (duration == Duration.zero) '0분',
  ].join(' ');
}

/// 저장소 생성은 앱 조립 계층에 맡기고, 주입된 저장 계약만 사용한다.
class RoutineLibraryScreen extends StatefulWidget {
  const RoutineLibraryScreen({super.key, this.store, required this.openStore});
  final RoutineStore? store;
  final Future<RoutineStore> Function() openStore;

  @override
  State<RoutineLibraryScreen> createState() => _RoutineLibraryScreenState();
}

class _RoutineLibraryScreenState extends State<RoutineLibraryScreen> {
  RoutineStore? _store;
  List<Routine> _routines = [];
  bool _loading = false;
  bool _busy = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.store == null) _store?.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || _loading || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _store ??= widget.store ?? await widget.openStore();
      if (!mounted) {
        if (widget.store == null) await _store!.close();
        return;
      }
      final routines = await _store!.listRoutines();
      if (!mounted) return;
      setState(() {
        _routines = routines;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '루틴을 불러오지 못했어요. 다시 시도해 주세요.';
        });
      }
    }
  }

  Future<void> _edit([Routine? routine]) async {
    if (_busy || _loading || _store == null) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    final ids = _routines.map((r) => r.id).toSet();
    var id = routine?.id ?? _newId();
    while (routine == null && ids.contains(id)) {
      id = _newId();
    }
    setState(() => _busy = true);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            RoutineEditorScreen(store: _store!, routine: routine, newId: id),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved != true) return;
    await _load();
  }

  Future<void> _delete(Routine routine) async {
    if (!mounted || _busy || _loading || _error != null) return;
    // 확인창을 여러 번 열거나 삭제 요청을 중복 전송하지 않는다.
    setState(() => _busy = true);
    final confirmed = await showConfirmation(
      context: context,
      title: '루틴을 삭제할까요?',
      message: '“${routine.name}” 루틴을 삭제해요. 과거 실행 기록은 유지돼요.',
      confirmLabel: '삭제',
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }
    setState(() => _deleting = true);
    try {
      await _store!.deleteRoutine(routine.id);
      if (!mounted) return;
      setState(() {
        _routines = _routines.where((r) => r.id != routine.id).toList();
        _busy = false;
        _deleting = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('루틴을 삭제했어요.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _deleting = false;
      });
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StoreActionBlocked
                ? error.message
                : '루틴을 삭제하지 못했어요. 다시 시도해 주세요.',
          ),
          action: SnackBarAction(
            label: '다시 삭제',
            onPressed: () => _delete(routine),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('루틴'),
        actions: [
          IconButton(
            tooltip: '루틴 새로고침',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: Text('루틴을 불러오는 중이에요.'))
            : _error != null
            ? SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(liveRegion: true, child: Text(_error!)),
                      TextButton(
                        onPressed: _load,
                        child: const Text('다시 불러오기'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('아침에 준비할 단계와 순서를 정해 보세요.'),
                  const SizedBox(height: 16),
                  if (_routines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text('아직 등록한 루틴이 없어요. 새 루틴을 등록해 주세요.'),
                    ),
                  for (final routine in _routines)
                    Card(
                      child: ListTile(
                        title: Text(
                          routine.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${routine.steps.length}단계 · 총 예상 시간 ${_durationText(routine.expected)}',
                        ),
                        onTap: _busy ? null : () => _edit(routine),
                        trailing: IconButton(
                          tooltip: '${routine.name} 삭제',
                          onPressed: _busy ? null : () => _delete(routine),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('루틴 등록'),
                  ),
                  if (_deleting)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: Text('삭제 중…')),
                    ),
                ],
              ),
      ),
    ),
  );
}

class _StepDraft {
  _StepDraft({required this.id, String name = '', this.originalDuration})
    : name = TextEditingController(text: name),
      minutes = TextEditingController(
        text: originalDuration == null ? '' : '${originalDuration.inMinutes}',
      );
  final String id;
  final TextEditingController name;
  final TextEditingController minutes;
  final Duration? originalDuration;
  bool durationEdited = false;
  final nameKey = GlobalKey<FormFieldState<String>>();
  final minutesKey = GlobalKey<FormFieldState<String>>();
  Duration? get duration {
    if (originalDuration != null && !durationEdited) {
      return originalDuration;
    }
    if (!RegExp(r'^\d+$').hasMatch(minutes.text.trim())) return null;
    final value = int.tryParse(minutes.text.trim());
    return value == null || value < 1 || value > 1440
        ? null
        : Duration(minutes: value);
  }

  void dispose() {
    name.dispose();
    minutes.dispose();
  }
}

class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({
    super.key,
    required this.store,
    required this.newId,
    this.routine,
  });
  final RoutineStore store;
  final Routine? routine;
  final String newId;

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _nameKey = GlobalKey<FormFieldState<String>>();
  late final TextEditingController _name;
  final List<_StepDraft> _steps = [];
  final List<_StepDraft> _retired = [];
  late final String _initialFingerprint;
  bool _saving = false;
  bool _allowPop = false;
  bool _confirmingExit = false;
  String? _error;
  bool _submitted = false;
  String? get _structureError => !_submitted
      ? null
      : _steps.isEmpty
      ? '단계를 한 개 이상 추가해 주세요.'
      : _total > const Duration(hours: 24)
      ? '루틴 전체 예상 시간은 24시간을 넘을 수 없어요.'
      : null;

  String _fingerprint() => jsonEncode([
    _name.text,
    for (final step in _steps)
      [
        step.id,
        step.name.text,
        step.minutes.text,
        step.duration?.inMicroseconds,
      ],
  ]);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.routine?.name ?? '');
    for (final step in widget.routine?.steps ?? <RoutineStep>[]) {
      _steps.add(
        _StepDraft(
          id: step.id,
          name: step.name,
          originalDuration: step.expected,
        ),
      );
    }
    if (widget.routine == null) _steps.add(_StepDraft(id: _newId()));
    _initialFingerprint = _fingerprint();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final step in [..._steps, ..._retired]) {
      step.dispose();
    }
    super.dispose();
  }

  Future<void> _leave() async {
    if (!mounted || _saving || _confirmingExit || _allowPop) return;
    _confirmingExit = true;
    var discard = _fingerprint() == _initialFingerprint;
    if (!discard) {
      discard = await showConfirmation(
        context: context,
        title: '변경한 내용을 저장하지 않고 나갈까요?',
        message: '저장하지 않은 변경 내용은 사라져요.',
        cancelLabel: '계속 수정',
        confirmLabel: '저장하지 않고 나가기',
      );
    }
    _confirmingExit = false;
    if (!mounted || !discard) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, false);
    });
  }

  void _addStep() {
    final used = [..._steps, ..._retired].map((s) => s.id).toSet();
    var id = _newId();
    while (used.contains(id)) {
      id = _newId();
    }
    setState(() {
      _steps.add(_StepDraft(id: id));
    });
  }

  void _move(int index, int delta) {
    setState(() {
      final step = _steps.removeAt(index);
      _steps.insert(index + delta, step);
    });
  }

  Duration get _total => _steps.fold(
    Duration.zero,
    (sum, step) => sum + (step.duration ?? Duration.zero),
  );

  Future<void> _save() async {
    if (_saving) return;
    final valid = _form.currentState!.validate();
    setState(() => _submitted = true);
    if (!valid || _structureError != null) {
      final keys = [
        _nameKey,
        for (final step in _steps) ...[step.nameKey, step.minutesKey],
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
      _error = null;
    });
    try {
      final routine = Routine(
        id: widget.routine?.id ?? widget.newId,
        name: _name.text.trim(),
        steps: [
          for (final step in _steps)
            RoutineStep(
              id: step.id,
              name: step.name.text.trim(),
              expected: step.duration!,
            ),
        ],
      );
      await widget.store.saveRoutine(routine);
      if (!mounted) return;
      setState(() {
        _allowPop = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('루틴을 저장했어요.')));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StoreActionBlocked
              ? error.message
              : '루틴을 저장하지 못했어요. 입력한 내용은 유지돼요. 다시 시도해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.routine == null ? '루틴 등록' : '루틴 수정'),
        leading: IconButton(
          tooltip: '편집 취소',
          onPressed: _saving ? null : _leave,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: _nameKey,
                      controller: _name,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: '루틴명',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '루틴명을 입력해 주세요.'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '준비 단계',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      '위·아래 버튼으로 단계 순서를 바꿀 수 있어요. 예상 시간은 분 단위로 입력해 주세요.',
                    ),
                    for (var index = 0; index < _steps.length; index++)
                      _stepCard(_steps[index], index),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _addStep,
                      icon: const Icon(Icons.add),
                      label: const Text('단계 추가'),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        '총 예상 시간: ${_durationText(_total)}${_steps.any((s) => s.duration == null) ? ' (미입력 단계 제외)' : ''}',
                      ),
                    ),
                    if (_structureError != null)
                      Text(
                        _structureError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_error != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(
                        _saving
                            ? '저장 중…'
                            : _error != null
                            ? '다시 저장'
                            : '루틴 저장',
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

  Widget _stepCard(_StepDraft step, int index) => Card(
    key: ValueKey(step.id),
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${index + 1}단계',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Wrap(
            children: [
              IconButton(
                tooltip: '${index + 1}단계 위로',
                onPressed: _saving || index == 0
                    ? null
                    : () => _move(index, -1),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: '${index + 1}단계 아래로',
                onPressed: _saving || index == _steps.length - 1
                    ? null
                    : () => _move(index, 1),
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: '${index + 1}단계 삭제',
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _retired.add(_steps.removeAt(index));
                      }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          TextFormField(
            key: step.nameKey,
            controller: step.name,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: '${index + 1}단계 이름',
              border: const OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? '단계 이름을 입력해 주세요.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: step.minutesKey,
            controller: step.minutes,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() => step.durationEdited = true),
            decoration: InputDecoration(
              labelText: '${index + 1}단계 예상 시간',
              suffixText: '분',
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '예상 소요시간을 입력해 주세요.';
              }
              if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
                return '예상 소요시간을 정수로 입력해 주세요.';
              }
              if (step.duration == null) {
                return '예상 소요시간은 1분부터 1440분까지 입력해 주세요.';
              }
              return null;
            },
          ),
          if (step.originalDuration != null &&
              step.originalDuration!.inMicroseconds %
                      Duration.microsecondsPerMinute !=
                  0)
            Text(
              '기존 예상 시간: ${_durationText(step.originalDuration!)}. 시간을 수정하면 분 단위로 적용돼요.',
            ),
        ],
      ),
    ),
  );
}
