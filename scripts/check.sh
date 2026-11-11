#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -d "$project_root/scripts/tests" ]]; then
  python3 -m unittest discover -s "$project_root/scripts/tests" -v
fi
cd "$project_root/app"

flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test

if [[ -d android/app/src/test ]]; then
  # Flutter가 생성하는 wrapper는 Git에서 제외된다. 새 checkout에서는 먼저 준비한다.
  if [[ ! -f android/gradlew ]]; then
    flutter build apk --debug --no-pub
  fi
  (
    cd android
    bash ./gradlew :app:testDebugUnitTest
  )
fi
