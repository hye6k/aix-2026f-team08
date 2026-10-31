# 9주차 활동지 / Week 9 Worksheet

**개발 착수 / Starting development**

- 작성일 / Date: 
- 참여자 / Present: 

---

## ① 착수 점검표 / Start checklist

수업 시작 후 10분 안에 확인합니다. 체크되지 않은 항목이 있으면 그것부터 해결하고 개발을 시작합니다.
*Check within the first 10 minutes. Fix any unchecked item before you start coding.*

- [ ] 초기 파일이 저장소에 올라와 있다 / Initial files are in the repository
- [ ] 7주차 이슈가 GitHub에 등록되어 있고 담당자가 지정되어 있다 / Week 7 issues are on GitHub with owners
- [ ] 팀원 모두 같은 환경에서 실행된다 / Everyone can run it in the same environment
- [ ] 브랜치 규칙을 정했다 / Branch rule agreed — 

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

---

> 수업 종료 시 커밋하세요 / Commit this at the end of class
> `git add docs/week-09.md && git commit -m "docs: 9주차 활동지 작성"`


### Android 관측 도구 판정 보완 — 2026-10-31, 강동혁

- 관련 이슈: [#7](https://github.com/hye6k/aix-2026f-team08/issues/7). 권한 철회 후 기존 알람이 수신되거나 Task 제거 후 화면 신호가 수신돼도 PASS가 될 수 있던 자동 판정 결함을 수정했다.
- 최초 알람 예약 성공을 확인한 뒤 권한을 철회하며, 각 관측값을 PASS 조건에 반영했다.
- ADB·시간 대기를 대체한 회귀 검사 9건을 통과했고 수정 전 코드에서 결함 재현 사례가 실패함을 확인했다. CI에 같은 검사를 추가했다. 실제 Android 상태별 13개 관측을 새로 실행한 결과와 구분한다.
- 실기기 소리·진동·절전 검증과 제품 통합은 남아 있으며 이슈 종료나 원격 PR 생성은 수행하지 않았다.
