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

### 2026-11-07 #22 명세 대조 보완

T17의 “후보 감지 시 확인 요청”에 대응하는 Android 알림 호출이 빠져 있어 후보 전용 알림 표시·제거를 추가했다. 알람 예약과 분리한 집중 테스트 10건과 네이티브 debug 빌드를 확인했다. 실제 세션 변화 연결은 #24에서 확인한다.

## 2026-11-09 Android PR #33 리뷰 대응 (#22)

- 새 예약·저장 확인 전 이전 예약과 현재 울림을 취소하던 경로를 보완했다. ID+시각 토큰으로 변경하여 교체 실패 중 이전 PendingIntent extras 변조도 피한다.
- 네이티브 다시 울림 실패·권한 철회 오류를 보존하고 앱 복귀 시 네이티브 안내창과 권한 설정 경로를 연결했다. 큐 확인 처리와 사용자 안내 확인을 분리한다.
- Kotlin 예약 교체 JVM10건, Flutter51/Python20·분석·debug 빌드를 통과했다. 실제 소리·진동·제조사 절전은 T13/#17에서 별도 검증한다.
- API36에서 미래 예약 후 알림 권한 철회·새 예약 거부·기존 AlarmManager 항목 보존을 확인했다. 실제 Receiver의 오류 기록과 별도 프로세스 재실행 후 사용자 안내창도 확인했다. 테스트 진입점으로 실행했으며 실제 소리·진동 전달을 성공 처리하지 않았다.
