#!/usr/bin/env bash
set -euo pipefail

: "${ANDROID_SERIAL:?ANDROID_SERIAL에 검증할 Android 기기 ID를 명시하세요. 예: emulator-5580}"
package=io.github.hye6k.morning_routine
activity="$package/.ProbeActivity"
adb_args=(-s "$ANDROID_SERIAL")
case "${1:-status}" in
  status)
    adb "${adb_args[@]}" get-state
    adb "${adb_args[@]}" shell getprop sys.boot_completed
    ;;
  open)
    adb "${adb_args[@]}" shell am start -W -n "$activity"
    ;;
  schedule)
    adb "${adb_args[@]}" shell am start -W -n "$activity" --es action schedule --ei delay_seconds "${2:-30}"
    ;;
  cancel)
    adb "${adb_args[@]}" shell am start -W -n "$activity" --es action cancel
    ;;
  screen)
    adb "${adb_args[@]}" shell input keyevent 223
    sleep 1
    adb "${adb_args[@]}" shell input keyevent 224
    ;;
  background)
    adb "${adb_args[@]}" shell input keyevent 3
    ;;
  force-stop)
    adb "${adb_args[@]}" shell am force-stop "$package"
    ;;
  log)
    adb "${adb_args[@]}" shell run-as "$package" cat shared_prefs/android_probe.xml
    ;;
  *)
    echo '사용법: bash scripts/android-probe.sh status|open|schedule [초]|cancel|screen|background|force-stop|log' >&2
    exit 2
    ;;
esac
