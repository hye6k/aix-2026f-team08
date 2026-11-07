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

### 2026-11-07 #8 실행 스냅샷 보존 회귀 수정

버전 증가만으로 실행 당시 이름·예상 시간·시작 시각을 바꾸거나 갱신 시각을 앞당기고 완료 단계를 미완료로 되돌리는 다섯 경로를 실제 SQLite 테스트로 재현했다. 저장 시 기존 스냅샷과 비교하는 검증을 추가했고 수정 후 저장 집중 11건과 정적 분석을 통과했다. 정상 상태 전이는 유지한다.
