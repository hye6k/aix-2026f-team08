import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'morning_runtime.dart';
import '../application/session_routine_store.dart';

class MorningBootstrap extends StatefulWidget {
  const MorningBootstrap({super.key, this.openRuntime});
  final Future<MorningRuntime> Function()? openRuntime;
  @override
  State<MorningBootstrap> createState() => _MorningBootstrapState();
}

class _MorningBootstrapState extends State<MorningBootstrap> {
  MorningRuntime? _runtime;
  bool _failed = false;
  bool _opening = false;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    setState(() => _failed = false);
    try {
      final runtime =
          await (widget.openRuntime?.call() ?? MorningRuntime.open());
      if (!mounted) {
        await runtime.close();
        return;
      }
      setState(() => _runtime = runtime);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    final runtime = _runtime;
    if (runtime != null) unawaited(runtime.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    if (runtime != null) {
      return MorningScope(
        runtime: runtime,
        child: MorningRoutineApp(
          messengerKey: _messenger,
          runtime: runtime,
          store: SessionRoutineStore(
            runtime.session,
            onAlarmPending: () {
              if (!mounted) return;
              _messenger.currentState?.showSnackBar(
                const SnackBar(
                  content: Text('설정은 저장했지만 알람 적용이 대기 중이에요. 알람 상태를 확인해 주세요.'),
                ),
              );
            },
          ),
        ),
      );
    }
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('저장된 정보를 불러오지 못했어요.'),
                    FilledButton(onPressed: _open, child: const Text('다시 시도')),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
