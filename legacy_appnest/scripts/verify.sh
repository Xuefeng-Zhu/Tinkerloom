#!/usr/bin/env bash
set -euo pipefail
appnest_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$appnest_root"
dart analyze --fatal-infos
# Serverpod rewrites generated protocol and test-tool files. Check authored Dart
# sources without formatting generator output by hand.
find \
  appnest_server/lib appnest_server/test appnest_server/bin appnest_client/bin \
  appnest_flutter/lib appnest_flutter/test packages scripts \
  -type f -name '*.dart' \
  ! -path 'appnest_server/lib/src/generated/*' \
  ! -path 'appnest_server/test/integration/test_tools/*' -print0 \
  | xargs -0 dart format --output=none --set-exit-if-changed
cd "$appnest_root/packages/appnest_spec"
# Exercise both 23- and 25-hour local days in the relative-day contract tests.
TZ=America/Los_Angeles dart test
cd "$appnest_root/packages/appnest_renderer"
flutter test
cd "$appnest_root/appnest_flutter"
flutter test
cd "$appnest_root/appnest_server"
dart test --concurrency=1
cd "$appnest_root"
dart run scripts/restart_smoke.dart
