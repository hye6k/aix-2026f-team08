# 개발 전용 Android 활동 신호·알람 실험

관련 이슈: [#7 / T02](https://github.com/hye6k/aix-2026f-team08/issues/7).

`ProbeActivity`와 `ProbeAlarmReceiver`는 `src/debug`에만 포함된다. 릴리스에는 포함하지 않는다.
실제 기상을 판단하는 기능이 아니라 OS 신호 수신 가능성을 관측하는 도구다.
사용자용 Flutter 화면·상태·DB와 연결하지 않았으며 알람의 최종 제품 구현 선택을 의미하지 않는다.

## 실행

```bash
cd app
flutter build apk --debug
cd ..
export ANDROID_SERIAL=emulator-5580  # adb devices에서 확인한 검증 기기 ID
adb -s "$ANDROID_SERIAL" install -r app/build/app/outputs/flutter-apk/app-debug.apk
bash scripts/android-probe.sh open
```

실험 화면에서 정확한 알람 권한과 알림 권한을 설정한 뒤 예약한다. 권한 거부 상태도 따로 시험한다.
테스트 기기에 이미 개인 데이터가 있는 경우 앱 삭제나 데이터 초기화 없이 진행한다.

```bash
bash scripts/android-probe.sh screen
bash scripts/android-probe.sh schedule 30
bash scripts/android-probe.sh background
bash scripts/android-probe.sh log
```

예약 시각 이후 로그를 다시 조회해 `ALARM_RECEIVED`를 확인한다.
알람을 수신했다는 기록과 실제 소리·진동 확인은 별개다. `NOTIFICATION_REQUESTED`와 `VIBRATION_REQUESTED`는 API 호출 기록이며 하드웨어 동작 성공 판정이 아니다.
로그는 앱 내부 개발용 SharedPreferences에 최근 200건만 저장한다. 외부 전송하지 않는다.

## 감지 실험

- 화면 전원 버튼을 누르거나 `screen` 명령을 사용해 실제 OS 화면 켜짐을 발생시킨다.
- 기대 로그: `ACTIVITY_SIGNAL android.intent.action.SCREEN_ON`.
- 잠금을 해제했을 때는 `USER_PRESENT` 수신 여부도 관측한다. 화면 켜짐과 잠금 해제를 구분한다.
- 동적 리시버는 Activity 생성 시 등록하고 파괴 시 해제한다. 앱이 백그라운드에 있어도 Activity/프로세스가 유지되는 상황과 제거된 상황을 구분한다.
- 앱 재개(resume)만을 화면 켜짐 수신의 증거로 사용하지 않는다.
- 프로세스 종료 뒤 자동 활동 감지를 보장하지 않는다. 이 제한을 기록하고 T02에서 감지 방식·지원 범위를 판단한다.

## 알람 실험

- 권한 없이 예약: `EXACT_ALARM_PERMISSION_DENIED`, 예약 없음.
- 권한 승인 후 예약: `ALARM_SCHEDULED`, 지정 시각 이후 `ALARM_RECEIVED` 확인.
- 같은 예약 번호로 재예약: 기존 PendingIntent가 갱신되는지 확인.
- `cancel` 후 기존 예약 시각 경과: 취소된 알람이 수신되지 않는지 확인.
- 앱 백그라운드·최근 앱 제거·강제 종료·재부팅은 각각 따로 관측한다.
- 이 실험 도구에는 재부팅 후 예약 복원 기능이 없다. 재부팅 뒤 재예약되는 것으로 설명하지 않는다.
- 정확한 알람 설정·알림 설정 변경 후 결과를 관측한다. 권한 화면에서 돌아왔다는 이유만으로 승인으로 간주하지 않는다.

명령 `force-stop`은 지정한 검증 앱을 강제 종료한다. 다른 앱이나 기기 전체를 종료하지 않는다.
강제 종료 이후의 제약을 일반 백그라운드 실행과 섞어서 기록하지 않는다.

## 결과 작성

`docs/android-validation.md`에 검증 일시, 기기/API, 에뮬레이터/실기기, 권한, 앱 상태, 조작, 실제 로그와 소리·진동 관찰 결과를 적는다.
APK 빌드·에뮬레이터 실행·실기기 동작을 각각 구분하며 T02의 완료 여부를 판단한다.
