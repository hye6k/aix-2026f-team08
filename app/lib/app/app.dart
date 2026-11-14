import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../presentation/home_screen.dart';
import '../domain/ports.dart';
import '../data/sqlite_store.dart';
import '../application/session_routine_store.dart';
import '../presentation/integrated_home.dart';
import 'morning_runtime.dart';

class MorningRoutineApp extends StatelessWidget {
  const MorningRoutineApp({
    super.key,
    this.store,
    this.openStore,
    this.messengerKey,
    this.runtime,
  });
  final RoutineStore? store;
  final Future<RoutineStore> Function()? openStore;
  final GlobalKey<ScaffoldMessengerState>? messengerKey;
  final MorningRuntime? runtime;

  @override
  Widget build(BuildContext context) {
    final editor = store;
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      title: '수면과 아침 루틴',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF416C63)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF416C63),
          brightness: Brightness.dark,
        ),
      ),
      home: runtime == null
          ? HomeScreen(
              store: store,
              openStore: openStore ?? SqliteRoutineStore.openDefault,
            )
          : IntegratedHomeScreen(
              runtime: runtime!,
              store: editor is SessionRoutineStore
                  ? editor
                  : SessionRoutineStore(runtime!.session),
            ),
    );
  }
}
