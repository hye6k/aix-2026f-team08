import 'package:flutter_test/flutter_test.dart';
import 'package:morning_routine/app/app.dart';

void main() {
  testWidgets('비교 화면에서 시안과 기존 앱을 각각 열고 돌아온다', (tester) async {
    await tester.pumpWidget(const MorningRoutineApp(compareUi: true));
    expect(find.text('두 가지 흐름을 비교해 보세요'), findsOneWidget);
    await tester.tap(find.text('새 UX 시안 보기'));
    await tester.pumpAndSettle();
    expect(find.text('아침을 함께 준비할게요'), findsOneWidget);
    expect(find.textContaining('저장·실제 알림 없음'), findsOneWidget);
    await tester.ensureVisible(find.text('예시 화면 계속 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('예시 화면 계속 보기'));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 아침'), findsOneWidget);
    expect(find.textContaining('마감 시각에 도착해요'), findsOneWidget);
    await tester.tap(find.text('기록').last);
    await tester.pumpAndSettle();
    expect(find.text('나의 아침 기록'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('두 가지 흐름을 비교해 보세요'), findsOneWidget);
    await tester.tap(find.text('기존 앱 보기'));
    await tester.pumpAndSettle();
    expect(find.text('나에게 맞는 아침을 준비해요'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('두 가지 흐름을 비교해 보세요'), findsOneWidget);
  });
  testWidgets('비교 플래그가 없으면 기존 앱이 바로 열린다', (tester) async {
    await tester.pumpWidget(const MorningRoutineApp());
    expect(find.text('나에게 맞는 아침을 준비해요'), findsOneWidget);
    expect(find.text('두 가지 흐름을 비교해 보세요'), findsNothing);
  });
}
