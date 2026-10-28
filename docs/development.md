# 개발 환경과 작업 기준

## 범위와 현재 상태

5~7주차 문서를 기준으로 Flutter + Dart, Android 우선, 기기 내부 저장을 사용한다.
서버·회원가입·기기 간 동기화·iOS는 이번 범위에 포함하지 않는다.
`memo-seed/`는 2주차 메모 검색 실습 자료이며 앱 서버가 아니다.

현재 `app/`은 한국어 계획·루틴·기록 탭을 가진 실행 가능한 초기 화면이다.
설정·DB 스키마·시간 계산·알람·기상 감지·루틴 실행은 후속 태스크에서 구현한다.
SQLite 패키지를 설치한 사실과 영속성 기능 구현을 구분한다.

## 공통 버전

| 항목 | 기준 |
|---|---|
| Flutter | **3.47.8**, 루트 `.flutter-version` |
| Dart | **3.13.7**, 위 Flutter SDK에 포함 |
| JDK | **21**, 루트 `.java-version` (로컬 검증: Temurin 21.0.13) |
| Android SDK | compile/target **36**, Build Tools **36.0.0** |
| 최소 Android API | **24**, Flutter 기본값; 실제 지원 기기는 T02에서 확인 |
| NDK | **28.2.13676358**, Flutter 기본값 |
| Gradle / Android Gradle Plugin | **9.3.1 / 9.1.0**, 생성된 설정 사용 |
| Kotlin plugin | **2.4.0**, 생성된 설정 사용 |

`app/pubspec.lock`을 커밋하여 패키지 버전을 공유한다. 업그레이드는 별도 변경으로 검증한다.
JDK 실행 버전은 21이며 앱 Java/Kotlin 바이트코드 타깃은 생성 템플릿의 17을 유지한다.
앱 ID는 `io.github.hye6k.morning_routine`이며 배포 전 최종 명칭·서명 정책을 확정한다.

## 설치와 실행

1. [Flutter 공식 설치 안내](https://docs.flutter.dev/install/manual)와 [SDK 아카이브](https://docs.flutter.dev/install/archive)를 따라 `.flutter-version`의 버전을 설치하고 `flutter/bin`을 PATH에 추가한다. Dart를 별도로 설치하지 않는다.
2. JDK 21을 설치하고 `JAVA_HOME`을 지정한다. Android Studio 내장 Java를 쓰더라도 21인지 확인한다.
3. [Android 설정 안내](https://docs.flutter.dev/platform-integration/android/setup)에 따라 SDK, Platform Tools, Command-line Tools, API 36, Build Tools 36.0.0과 위 NDK를 설치한다. `ANDROID_HOME`을 SDK 경로로 지정한다. Android Studio는 권장 IDE이며 CLI 빌드의 필수 구성은 아니다.
4. `flutter doctor -v`로 Android toolchain을 확인한다. 라이선스 처리는 설치한 도구의 안내를 따른다. 최신 Android CLI는 `android sdk`를 제공하며 기존 `sdkmanager --licenses`는 더 이상 필요하지 않다고 표시할 수 있다.
5. Android 기기에서 개발자 옵션·USB 디버깅을 켜고 PC 연결을 승인한다. 에뮬레이터를 쓸 경우 SDK Manager에서 Emulator와 시스템 이미지를 설치하고 AVD를 만든다.

```bash
git clone https://github.com/hye6k/aix-2026f-team08.git
cd aix-2026f-team08
flutter --version
flutter doctor -v
flutter devices
cd app
flutter pub get --enforce-lockfile
flutter run -d <android-device-id>
```

예: `flutter devices`의 Android 기기 ID 또는 `emulator-5554`를 쓴다. Linux 데스크톱을 선택하지 않는다.
현재 앱에는 환경변수·API 키·`.env`가 필요하지 않다. 웹·Linux 데스크톱 도구 경고는 Android 빌드와 별개다.
이 PC의 SDK 설치 경로와 환경 활성화 방법은 개인 로컬 기록에 둔다.

## 검사와 빌드

SDK가 PATH에 있는 상태에서 저장소 루트에서 실행한다.

```bash
bash scripts/check.sh
cd app
flutter build apk --debug --no-pub
```

APK: `app/build/app/outputs/flutter-apk/app-debug.apk`.
현재 테스트는 한국어 앱 시작, 탭 이동, 작은 화면·큰 글자 레이아웃을 확인한다.
계산·상태 전이·DB·플랫폼 기능을 추가할 때 해당 완료 조건의 테스트를 추가한다.
GitHub Actions는 main 대상 PR·main push·수동 실행에서 같은 검사와 debug APK 빌드를 수행한다.
CI 파일 작성과 GitHub에서의 실제 실행은 구분한다.

현재 빌드는 개발용이다. 릴리스 템플릿의 debug 서명은 스토어 배포용 서명이 아니다.
릴리스 키·`key.properties`·비밀 환경변수·`local.properties`·빌드 산출물은 커밋하지 않는다.

## 계층과 도구 선택

```text
app/lib/
  main.dart             앱 시작
  app/                  테마·로케일·의존성 조립
  presentation/         화면·UI 상태
  domain/               순수 Dart 모델·계산·상태 전이·저장/플랫폼 계약
  data/                 SQLite 및 저장 구현 (T03)
  platform/             Android 알람·권한·활동 신호 어댑터 (T02 이후)
```

- **상태 관리:** 기본 `ChangeNotifier` + `ListenableBuilder`를 화면 모델에 사용한다. 의존성은 생성자로 주입한다. 현재 탭 선택처럼 화면 내부에서만 쓰는 상태는 `setState`로 관리한다. 작은 MVP에 코드 생성과 별도 상태 관리 패키지를 선제 도입하지 않는다.
- **로컬 DB:** SQLite + `sqflite`, DB 파일 경로는 `path`를 사용한다. 관계·순서·시각·실행 상태를 명시적으로 저장하고 트랜잭션과 스키마 버전을 관리하기 위한 선택이다. T03에서 실제 테이블과 마이그레이션을 정의한다.
- **플랫폼:** 플러그인은 T02 실기기 실험 뒤 정한다. 필요하면 Kotlin/MethodChannel을 사용한다. 현재 알람·위치·화면 감지 권한은 추가하지 않았다.
- **로직:** Flutter 위젯, sqflite, Android 구체 API에 의존하지 않는다. DB SQL과 OS 호출을 화면에 작성하지 않는다.

참고: [Flutter 아키텍처 권고](https://docs.flutter.dev/app-architecture/recommendations), [ChangeNotifier 안내](https://docs.flutter.dev/data-and-backend/state-mgmt/simple), [sqflite](https://pub.dev/packages/sqflite).

## 다음 작업과 완료 기준

1. **T01 잔여:** 테스트 기기·OS를 정하고 해당 Android 기기에서 초기 화면을 실행한다. APK 빌드만으로 완료 처리하지 않는다.
2. **T02:** [Android 검증 기록](android-validation.md)에 앱 실행 중·백그라운드·종료·강제 종료 조건별 화면 켜짐과 소리·진동 알람 결과를 기록한다. 플러그인과 지원 제약은 결과를 보고 채택한다.
3. **T12 병행:** 알람 해제/다시 울림, 후보 취소/중복/수동 확인, 자정 경계와 권한 거부 시나리오를 구체화한다.
4. **이후:** 5주차 의존 관계에 따라 T03 저장 모델, T06 시간 계산, T04/T05 입력 화면을 진행한다.

기상 후보는 사용자 확인 전까지 확정 기상 기록이 아니다. 알람 해제나 수동 루틴 시작으로 기상을 확정하지 않는다.
실제 기기 실험, 에뮬레이터 실험, 주입한 테스트 이벤트를 각각 구분한다.

## 협업 기록

브랜치·커밋·리뷰 규칙은 [6주차](week-06.md)를 따른다.
초기 설정 시 실제 GitHub 이슈 번호가 없어 `chore/android-bootstrap`을 사용했다. 이후 이슈 등록 후 번호를 연결한다.
설명 가능한 작업 단위마다 한국어 Conventional Commit을 남긴다.
설계 판단·채택/수정/폐기 이유·검증 결과는 기존 `PROMPTS.md`에 기록하며, 개인 메모와 머신 경로는 공유 문서에서 제외한다.
구현·검증 없이 활동지의 완료 체크나 인터뷰·실기기 검증 결과를 채우지 않는다.
