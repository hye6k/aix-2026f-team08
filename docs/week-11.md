# 11주차 활동지 / Week 11 Worksheet

**중간 데모와 상호 리뷰 / Interim demo and peer review**

- 작성일 / Date: 
- 참여자 / Present: 
- 결과보고서 / Report chapter: 8장 결과와 한계
- 최종 반영 / Feeds into: 협업 평가 근거 / collaboration evidence

---

## 데모 시나리오 / Demo scenario — 사용자 한 명의 이야기



## 시연 결과 / 실패 지점 / Result and failure point



## 상대 팀에 남긴 리뷰 / Reviews you left

- 질문 Question:
- 제안 Suggestion:
- 필수 Must-fix:

## 받은 리뷰 → 이슈 번호 / Reviews received → issues

- #12 / PR #31 리뷰에서 활성 단계 최소 잔여 시간의 적용 경계, 루틴 완료 후 출발 가정, 시계 역행 검사 범위를 확인했다. 기존 계산 동작을 명시하고 각 경계에 대한 자동 검사를 보완했다. 실제 출발·도착 감지와 마지막 계산 이후의 시계 변경 감지는 이 계산 범위에 포함하지 않는다.
- #23에서 계획·기상·루틴·알람의 세션 계약을 선행 기능이 병합된 main에 분리하고, 저장 실패와 예약 재시도·중복 조작·복원 경계를 자동 검사했다. SQLite와 Android 기동 연결은 #24에서 검증한다.
- PR #36 리뷰에서 대기 의도 없는 알람 재적용 실패의 복원 누락과 초기화 중 종료 시 구독 잔류를 재현하고, 저장 순서와 구독 정리를 수정해 회귀 검사했다.


## 성찰 / Reflection — 가장 약한 고리



---

> 수업 종료 시 커밋하세요 / Commit this at the end of class
> `git add docs/week-11.md && git commit -m "docs: 11주차 활동지 작성"`
