import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../presentation/home_screen.dart';
import '../domain/ports.dart';
import '../data/sqlite_store.dart';

class MorningRoutineApp extends StatelessWidget {
  const MorningRoutineApp({
    super.key,
    this.store,
    this.openStore,
    this.messengerKey,
  });
  final RoutineStore? store;
  final Future<RoutineStore> Function()? openStore;
  final GlobalKey<ScaffoldMessengerState>? messengerKey;

  @override
  Widget build(BuildContext context) {
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
      home: HomeScreen(
        store: store,
        openStore: openStore ?? SqliteRoutineStore.openDefault,
      ),
    );
  }
}
