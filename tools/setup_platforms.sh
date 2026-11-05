#!/usr/bin/env bash
# iOS/Android 폴더를 만들고 카메라·마이크 권한 등을 자동으로 넣는다.
# 맥에서 처음 한 번만 실행:  bash tools/setup_platforms.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d ios ] || [ ! -d android ]; then
  had_widget_test=0
  [ -f test/widget_test.dart ] && had_widget_test=1
  flutter create --org ai.stra --project-name gongbuhaera --platforms ios,android .
  # flutter create 가 만드는 기본 예제 테스트는 우리 앱과 맞지 않아 지운다
  if [ "$had_widget_test" = 0 ]; then rm -f test/widget_test.dart; fi
fi

python3 tools/patch_platforms.py
flutter pub get
echo "✅ 준비 완료. 이제 README 의 '실행하기' 를 따라 하세요."
