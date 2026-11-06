# 로직 계층

순수 Dart 모델, 시간 계산, 기상 후보 상태 전이, 루틴 진행 및 저장/플랫폼 인터페이스를 둔다.
Flutter 위젯, sqflite, Android API를 import하지 않는다.
`models.dart`와 `ports.dart`에 기기 독립 모델·저장·알람·활동 신호 계약을 정의했다.
계산·상태 처리 구현은 별도 기능 PR로 준비하며, 실제 OS 연동 완료는 T02 검증과 구분한다.
API와 제출 순서는 저장소의 `docs/development-contracts.md`를 따른다.
