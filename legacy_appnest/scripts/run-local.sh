#!/usr/bin/env bash
set -euo pipefail
appnest_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$appnest_root/appnest_flutter"
dart run "$appnest_root/scripts/init_local.dart"
flutter pub get
flutter build web --release --dart-define=SERVER_URL=http://localhost:8180/ --output=../appnest_server/web/app
cd "$appnest_root/appnest_server"
exec dart run bin/main.dart --apply-migrations "$@"
