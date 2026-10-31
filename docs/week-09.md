# 9주차 활동지 / Week 9 Worksheet

**개발 착수 / Starting development**

- 작성일 / Date: 
- 참여자 / Present: 

---

## ① 착수 점검표 / Start checklist

수업 시작 후 10분 안에 확인합니다. 체크되지 않은 항목이 있으면 그것부터 해결하고 개발을 시작합니다.
*Check within the first 10 minutes. Fix any unchecked item before you start coding.*

- [x] 초기 파일이 저장소에 올라와 있다 / Initial files are in the repository — PR #5 병합
- [ ] 7주차 이슈가 GitHub에 등록되어 있고 담당자가 지정되어 있다 / Week 7 issues are on GitHub with owners
- [ ] 팀원 모두 같은 환경에서 실행된다 / Everyone can run it in the same environment
- [x] 브랜치 규칙을 정했다 / Branch rule agreed — 6주차 규칙과 실제 이슈 번호 사용

---

## ② 개발 일정 / Development schedule

5주차 **작업 순서**와 7주차 **이슈·마일스톤**을 바탕으로 이슈를 주차별로 배치합니다.
*Place your issues week by week, based on the Week 5 work order and Week 7 issues and milestones.*

- 11주차에 MVP가 동작해야 합니다. / Fill backwards from the deadlines.
- 선행 이슈가 끝나기 전에 뒤 이슈를 넣지 않습니다. / Never schedule an issue before the ones it depends on.
- 한 사람에게 몰리지 않았는지 확인합니다. / Check that no one is overloaded.

| 주차 Week | 수업 일정 Class | 끝낼 이슈 # Issues to close | 담당 Owner |
|---|---|---|---|
| 9주차 | 개발 착수 |  |  |
| 10주차 | 막힘 진단 · 데모 시나리오 초안 |  |  |
| 11주차 | **MVP 완료 · 중간 데모** |  |  |
| 12주차 | 핵심 경로 테스트 |  |  |
| 13주차 | **배포 · 실행 패키지** |  |  |

> 일정이 맞지 않으면 기능을 줄입니다. 뺀 기능은 5주차 Won't 목록에 옮깁니다.
> *If it doesn't fit, cut scope and move the feature to your Week 5 Won't list.*

---

## ③ 이번 주 목표 이슈 / This week's issues

| # | 제목 Title | 담당 Owner | 완료 Done |
|---|---|---|---|
|  |  |  | [ ] |
|  |  |  | [ ] |
|  |  |  | [ ] |

---

## ④ 오늘 진행한 것 / Progress today

- [ ] 이번 활동에서 AI를 사용했다면 `PROMPTS.md`에 기록했습니다 / Logged any AI use in `PROMPTS.md`

### 추가 개발 기록 — 2026-10-31, 강동혁

기기 없이 가능한 담당 구현을 독립 PR 단위로 준비했다. 아래의 “검증 완료”는 해당 코드·테스트 범위의 결과이며 전체 태스크 완료나 PR 병합을 뜻하지 않는다.
중요한 판단은 문안을 제시하고 사용자에게 허락받은 항목부터 `PROMPTS.md`에 기록했다. 추가 판단은 승인 대기 상태를 구분한다.

| 이슈 / 태스크 | 해결·구현한 내용 | 확인 방법과 결과 | 남은 완료 조건 |
|---|---|---|---|
| [#6](https://github.com/hye6k/aix-2026f-team08/issues/6) / 공통 | 순수 Dart 모델·저장·플랫폼 계약, 잘못된 상태 거부 | 경계·불변식 자동 테스트 | PR 리뷰·병합 |
| [#7](https://github.com/hye6k/aix-2026f-team08/issues/7) / T02 준비 | debug 전용 화면 신호·알람 실험 도구와 재현 스크립트 | debug/release APK 빌드 및 release에 실험 Activity·권한이 없음을 확인 | Android 실행·상태별 관측·실기기 소리/진동 검증 |
| [#8](https://github.com/hye6k/aix-2026f-team08/issues/8) / T03 | 설정·루틴·후보·실행 저장, 불변 기록과 오래된 저장 보호 | 실제 SQLite 파일 재개방·수정/삭제·상태 복원 등 6건 통과 | Android 앱 재실행과 화면 연결 |
| [#9](https://github.com/hye6k/aix-2026f-team08/issues/9) / T06 | 준비 시간·취침·권장 기상·실제 알람·출발 계산 | 수동/권장 모드·자정/연도 경계 4건 통과 | PR 리뷰·병합, 입력 화면 연결 |
| [#10](https://github.com/hye6k/aix-2026f-team08/issues/10) / T08 | 후보 구간·중복·확인·취소·재감지·수동 보완 | 테스트 이벤트 시나리오 5건 통과 | 실제 활동 신호 연결과 검증 |
| [#11](https://github.com/hye6k/aix-2026f-team08/issues/11) / T09·T14 | 루틴 시작·단계 조작·중복 방지·중단·복구 스냅샷 | 실행 상태·재구성·앱을 닫아 둔 경과 시간 등 5건 통과 | 저장·UI 통합과 Android 재실행 확인 |
| [#12](https://github.com/hye6k/aix-2026f-team08/issues/12) / T10 | 조건부 도착·지각·진행 상태별 잔여 계산 | 초과 단계·분 올림·날짜 경계 등 4건 통과 | 화면 갱신 연결 |
| [#13](https://github.com/hye6k/aix-2026f-team08/issues/13) / T15 | 완료한 단계 기록 기반 소요시간 보정 | 표본 부족·이상치·최근 기록·중복·제외 조건 5건 통과 | PR 리뷰·병합과 저장된 실제 기록 연결 |
| [#14](https://github.com/hye6k/aix-2026f-team08/issues/14) / T17 조정 | 예약·취소·권한·오류·동시 변경·다시 울림 | 주입한 가짜 플랫폼으로 5건 통과 | 실제 OS 알람 어댑터와 기기 검증 |

T01 이슈 #4와 플랫폼 통합은 미완료로 유지한다. 이슈는 완료 조건을 충족하고 PR이 병합된 후 닫는다.
다음 제출 순서는 `docs/development-contracts.md`를 따른다. PR이 실제 생성되면 이 표에 링크를 보완한다.

추가 검증: 준비한 전체 브랜치를 합쳐 정적 분석·전체 테스트 45건과 debug APK 빌드가 통과했다. SQLite 파일을 재개방하며 핵심 흐름을 연결한 통합 테스트 4건을 포함한다. Android OS 신호는 이 결과에 포함되지 않는다.

---

> 수업 종료 시 커밋하세요 / Commit this at the end of class
> `git add docs/week-09.md && git commit -m "docs: 9주차 활동지 작성"`
