#!/usr/bin/env bash
# Offline checks only. The bounded Cloud smoke is deliberately a separate command.
set -euo pipefail
tinkerloom_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$tinkerloom_root"
mode="${1:---all}"
case "$mode" in --all|--client-only|--backend-only) ;; *) echo "Usage: scripts/verify.sh [--all|--client-only|--backend-only]" >&2; exit 2 ;; esac
export TINKERLOOM_ALLOW_CLOUD_TESTS=0
if [[ "$mode" != --backend-only ]]; then
  flutter pub get
  for package in packages/appnest_spec packages/appnest_renderer packages/tinkerloom_client apps/flutter; do
    flutter analyze --no-pub "$package"
  done
  dart format --output=none --set-exit-if-changed \
    packages/appnest_spec/lib packages/appnest_spec/test \
    packages/appnest_renderer/lib packages/appnest_renderer/test \
    packages/tinkerloom_client/lib packages/tinkerloom_client/test \
    apps/flutter/lib apps/flutter/test
  (cd packages/appnest_spec && TZ=America/Los_Angeles dart test)
  (cd packages/appnest_renderer && flutter test --no-pub)
  (cd packages/tinkerloom_client && flutter test --no-pub)
  (cd apps/flutter && flutter test --no-pub && flutter build web --release --no-pub)
fi
if [[ "$mode" != --client-only ]]; then
  backend_dart="${TINKERLOOM_BACKEND_DART:-dart}"
  backend_version="$("$backend_dart" --version 2>&1)"
  if [[ "$backend_version" != *"Dart SDK version: 3.11."* ]]; then
    echo "Backend verification requires Dart 3.11; set TINKERLOOM_BACKEND_DART to its executable." >&2
    exit 2
  fi
  (cd appwrite_backend/packages/appnest_spec && "$backend_dart" pub get && \
    "$backend_dart" analyze lib test && \
    "$backend_dart" format --output=none --set-exit-if-changed lib test && \
    "$backend_dart" test)
  for source in scripts/*.mjs; do node --check "$source"; done
  node --test scripts/live_smoke_denial.test.mjs scripts/live_collaboration_contract.test.mjs \
    scripts/live_full_contract.test.mjs scripts/live_media_smoke.test.mjs \
    scripts/live_reminder_contract.test.mjs scripts/live_ephemeral_accounts.test.mjs \
    scripts/transaction_observer.test.mjs
  (
    cd appwrite_backend
    "$backend_dart" pub get
    "$backend_dart" analyze lib test tool
    "$backend_dart" format --output=none --set-exit-if-changed lib test tool
    "$backend_dart" run test/service_check.dart
    "$backend_dart" run test/full_probe_fixture_check.dart
    "$backend_dart" test
    TINKERLOOM_TEST_DART="$backend_dart" node --test --test-concurrency=1 \
      ../scripts/live_activity_smoke.test.mjs ../scripts/live_media_pipeline.test.mjs \
      ../scripts/live_reminder_service.test.mjs ../scripts/live_full_read_retry_service.test.mjs
    "$backend_dart" run test/export_client_wire.dart --check test/fixtures/client_wire.json
    verify_output="$(mktemp -d "${TMPDIR:-/tmp}/tinkerloom-verify.XXXXXX")"
    "$backend_dart" compile aot-snapshot lib/main.dart -o "$verify_output/tinkerloom-core.aot"
    "$backend_dart" compile aot-snapshot lib/worker_main.dart -o "$verify_output/tinkerloom-worker.aot"
  )
fi
