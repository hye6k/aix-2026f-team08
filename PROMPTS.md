# AI 협업 기록 / AI Collaboration Log

작성 원칙: 프롬프트 나열이 아니라 **판단 근거**를 남긴다.
Principle: record your **reasoning**, not just prompts.

---

## [이슈 #1] 메모 검색 기능

**목표(스펙) / Spec**
- 입력 Input: 검색 키워드
- 처리 Processing: 메모의 제목 또는 본문에서 키워드 검색
- 출력 Output: 조건에 맞는 메모 목록
- 실패 조건 Failure: 

**요청한 프롬프트 요지 / Prompt (summary)**

메모의 제목과 본문에서 키워드를 검색하는 기능을 요청했다.
방식 A는 기능 요구만 제시했고, 방식 B는 프로젝트 규약, 기존 코드, 데이터베이스 스키마, 종료 조건을 함께 제시했다.

**결과에 대한 판단 / Decisions**
- 채택한 부분과 이유 / Accepted, because: 해당 없음
- 수정한 부분과 이유 / Changed, because: 해당 없음
- 폐기한 부분과 이유 / Rejected, because: 해당 없음

방식 A는 검색 기능 자체는 구현했지만 독립적인 HTML/JavaScript 애플리케이션 형태로 작성되었다.

방식 B는 기존 service.js, routes.js, 데이터베이스 구조를 반영해 검색 기능을 추가했다. 또한 user_id 조건과 빈 검색어 검증이 포함되었다.

**검증 방법 / How it was verified**

- 제목과 본문 검색 여부 확인
- 기존 코드 구조 반영 여부 확인
- user_id 조건 포함 여부 확인
- 빈 검색어 처리 여부 확인
- 프로젝트 규약 준수 여부 확인

---

## [이슈 #__] 제목 / Title

**목표(스펙) / Spec**
- 입력 Input:
- 처리 Processing:
- 출력 Output:
- 실패 조건 Failure:

**요청한 프롬프트 요지 / Prompt (summary)**

**결과에 대한 판단 / Decisions**
- 채택한 부분과 이유 / Accepted, because:
- 수정한 부분과 이유 / Changed, because:
- 폐기한 부분과 이유 / Rejected, because:

**검증 방법 / How it was verified**

---
(이슈 단위로 반복 / repeat per issue)

## [T01 / 이슈 #4] Android Flutter 앱 구성 (2026-10-28)

**목표 / Spec**
- 5~7주차의 Android 우선·로컬 저장·계층 분리 방향을 실행 가능한 Flutter 초기 앱과 공통 개발 환경에 반영한다.
- 기기 실행과 플랫폼 실험 없이 T01/T02를 완료 처리하지 않는다.


**결과에 대한 판단 / Decisions**
- 채택: Flutter 3.47.8/Dart 3.13.7, JDK 21과 생성된 Android 빌드 구성을 사용한다. SDK 버전 파일과 앱 lockfile을 공유해 환경 차이를 줄인다.
- 채택: 화면·순수 Dart 로직·데이터·Android 어댑터의 경계를 구분한다. 초기 탭은 `setState`, 화면 모델은 기본 `ChangeNotifier`/`ListenableBuilder`, 저장은 SQLite(`sqflite`)를 선택했다. 소규모 MVP에서 명시적인 상태·트랜잭션을 다루면서 코드 생성과 의존성을 줄이기 위한 판단이다. DB 스키마·영속성은 T03 후속 작업이다.
- 수정: Flutter 카운터 예제를 한국어 계획·루틴·기록 초기 화면으로 바꾸고 한국어 로케일과 시스템 테마를 적용했다. 초기 화면과 기능 완성을 구분하여 표시한다.
- 보류: 알람·활동 신호 플러그인과 권한은 T02 실기기 검증 후 선택한다. 라이브러리 설치만으로 백그라운드·종료 상태 동작을 보장할 수 없기 때문이다.
- 폐기: `memo-seed/`를 앱 서버로 사용하는 구성, 로그인/동기화, iOS 타깃. 수업 예제와 실제 앱을 혼동하지 않고 확정 범위를 지킨다.
- 기록: 팀에 필요한 판단은 이 문서에, 개인 작업 메모와 머신 경로는 Git이 추적하지 않는 로컬 기록에 둔다.

**검증 방법 / How it was verified**
- 의존성 설치, Dart 포맷, `flutter analyze` 통과.
- 한국어 시작·탭 이동 및 작은 화면/큰 글자 위젯 테스트 2건 통과.
- `flutter doctor -v`의 Android toolchain 통과. 실제 Android 기기는 연결되지 않았다.
- `bash scripts/check.sh`와 Android 디버그 APK 빌드 통과. 플랫폼 미검증 항목은 `docs/android-validation.md`에 기록한다.
- 공통 검사 스크립트 및 GitHub Actions 구성은 `docs/development.md`에 설명한다. 원격 CI 실행 여부는 로컬 검사와 구분한다.

## [이슈 #4 / PR #5] 협업 규칙 점검과 원격 게시 (2026-10-28)


**판단과 반영**
- 기존 커밋 제목은 6주차 형식을 지켰지만 브랜치의 실제 이슈 번호와 7주차 이슈 연결이 빠져 있었다. T01을 실제 이슈 #4로 등록하고 최신 main에서 규칙에 맞는 브랜치와 이슈 번호가 포함된 커밋으로 같은 변경을 옮겼다.
- 기존 원격 이력을 강제 변경하지 않고 작업 브랜치를 게시하여 한국어 초안 PR #5로 리뷰 경로를 마련했다. 이슈·코멘트·PR·리뷰의 한국어 작성 원칙을 6주차 문서와 개발 안내에 반영했다.
- 실기기 검증이 남아 있어 이슈를 자동 종료하는 PR 연결은 사용하지 않았다. main의 보호 규칙은 확인했으며, 필수 승인 수 0명과 실제 리뷰 대기를 구분해 기록했다.

**검증**
- 원격 main과의 기반 관계, 각 커밋의 형식·이슈 번호, 기존 세 커밋과 옮긴 변경의 파일 내용 일치를 확인했다.
- `bash scripts/check.sh` 재실행 통과. 앱 소스 변경은 없다.
- 개인 문서·로컬 SDK·자격 증명과 빌드 산출물의 Git 추적 제외를 재확인했다. PR 병합과 T01 완료는 후속 절차다.
