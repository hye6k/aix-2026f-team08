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

## 2026-11-07 Android 앱 연동 구현 검증 (#22)

- 앱용 MethodChannel/EventChannel 어댑터와 main 알람 수신기를 추가했다. 정확한 알람·알림 권한을 구분하고, 알람 해제·다시 울림은 기상 확정과 분리했다.
- 채널 경계 테스트 8건을 포함한 Flutter 테스트 49건, 정적 분석 및 debug APK 빌드를 통과했다.
- [연결 API·검증 절차·지원 제약](android-platform-adapter.md)을 작성했다. 제품 어댑터의 실기기 소리·진동·Deep Doze와 종료 상태 검증은 남아 있어 #22를 완료 처리하지 않는다.
- API 36 에뮬레이터에서 제품 채널의 예약·발생, 이벤트 조회·확인 처리, 발생 전 취소, 실제 화면 전환 신호 전달을 추가 확인했다. UI 전체 연결 및 실제 소리·진동 결과와 구분한다.
