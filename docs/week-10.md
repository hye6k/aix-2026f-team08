# 10주차 활동지 / Week 10 Worksheet

**막힘 진단 / Diagnosing blockers**

- 작성일 / Date: 
- 참여자 / Present: 
- 결과보고서 / Report chapter: 5장 구현 과정
- 최종 반영 / Feeds into: Won't 목록 갱신 / updated Won't list

---

## 막힌 지점 / What is blocked



## 유형 / Type

- [ ] 환경 Environment
- [ ] 이해 Understanding
- [ ] 설계 Design
- [ ] 범위 Scope

## 디버깅 요청 4요소 / Four parts of a debugging request

- 증상 Symptom:
- 재현 Steps:
- 기대 Expected:
- 실제 Actual:

## 진행 속도 / Progress

닫힌 이슈 Closed __ / 전체 Total __

## **버린 기능과 이유 / Features dropped and why**



## 데모 시나리오 초안 / Draft demo scenario



---

> 수업 종료 시 커밋하세요 / Commit this at the end of class
> `git add docs/week-10.md && git commit -m "docs: 10주차 활동지 작성"`

## 검증하지 않은 것 / Not verified  → `ETHICS.md` 4절

| 무엇을 검증하지 않았나 | 왜 | 남는 위험 |
|---|---|---|
|  |  |  |

## 2026-11-09 알람 조정 PR #32 리뷰 대응 (#14)

- 기존 예약 뒤 변경 실패로 예약이 사라지거나 부분 적용된 새 ID가 남는 두 경로를 재현했다.
- 실패한 새 예약 정리와 이전 미래 예약 복원을 시도하고, 최초/복원 오류·복원 성공 여부를 구조화해 반환한다. 만료·권한 거부 시 복원을 보장하지 않는다.
- 집중 10건을 통과했다. 네이티브 버튼 캐시 무효화와 날짜별 단발 예약 책임은 [복구 계약](alarm-recovery.md)에 명시했다. 실제 기기 검증은 별도다.
