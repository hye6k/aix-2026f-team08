# 수면과 아침 루틴

Android 전용 Flutter 앱. 저장소 루트의 `.flutter-version`으로 SDK를 맞춘다.

```bash
flutter pub get
flutter run -d <android-device-id>
```

설치·검사·빌드 방법과 지원 범위는 [개발 안내](../docs/development.md)를 따른다.
계획 탭의 **시간 설정**에서 목표·기상 설정을 저장하고, 루틴 탭의 **루틴 관리**에서
루틴 등록·수정·삭제 및 단계 순서 변경을 할 수 있다. 두 화면 모두 로컬 SQLite에 저장한다.
계획 결과와 기록 조회 화면은 후속 작업이다. 루틴 화면의 범위와 검증 결과는
[T05 구현 기록](../docs/t05-routine-editor.md)을 따른다.
기기 독립 모델·저장·계산·상태 처리와 플랫폼 실험은 PR 단위로 준비하고 검증한다.
