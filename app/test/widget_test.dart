import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/app.dart';

void main() {
  testWidgets('앱이 한국어로 시작되고 기본 화면을 이동할 수 있다', (tester) async {
    await tester.pumpWidget(const MorningRoutineApp());
    await tester.pumpAndSettle();

    expect(find.text('나에게 맞는 아침을 준비해요'), findsOneWidget);
    final context = tester.element(find.byType(NavigationBar));
    expect(Localizations.localeOf(context), const Locale('ko'));

    await tester.tap(find.text('루틴'));
    await tester.pumpAndSettle();
    expect(find.text('하루를 시작하는 나만의 순서'), findsOneWidget);

    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    expect(find.text('아침의 흐름을 돌아봐요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면과 큰 글자 설정에서 첫 화면이 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const MorningRoutineApp());
    await tester.pumpAndSettle();

    expect(find.text('수면과 아침 루틴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
