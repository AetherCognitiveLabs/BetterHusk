#!/bin/bash
# Typechecks the app target's Swift sources the way the Xcode build sees them:
# one module, the ObjC bridging header, the iPhone SDK. Catches the type-error
# class ("l10n pass" breakage, private(set) writes, missing symbols) without
# the 40+ minute dependency build.
#
# A single whole-module -typecheck walks every file serially (~20 min on the
# runner). Per-primary checks run in parallel instead: each invocation parses
# the module (cheap) but only typechecks its own primary file, so the union of
# results is the same diagnostics at a fraction of the wall time.
set -uo pipefail
cd "$(dirname "$0")/../.."

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
FILES="$(git ls-files 'src/app/Husk' 'src/app/Shared' | grep '\.swift$'; git ls-files 'src/app/HuskJITHelper/HuskJITMessages.swift')"

ARGS=(-typecheck
  -target arm64-apple-ios15.5
  -sdk "$SDK"
  -module-name Husk
  -parse-as-library
  -import-objc-header src/app/Husk/HuskBridge.h
  -I src/app/Husk
  -I src/ios-jit
  -I src/translation-layer
  -I src/translation-layer-next
  -Xcc -idirafter -Xcc tools/precheck/include)

# bash 3.2 (the runner's /bin/bash) has no `wait -n`, so concurrency is chunked:
# run up to $JOBS primaries, wait for the whole chunk, continue.
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fail=0
checked=0
pids=()
for f in $FILES; do
  xcrun --sdk iphoneos swiftc "${ARGS[@]}" -primary-file "$f" $FILES &
  pids+=($!)
  checked=$((checked + 1))
  if (( ${#pids[@]} >= JOBS )); then
    for p in "${pids[@]}"; do wait "$p" || fail=1; done
    pids=()
  fi
done
for p in "${pids[@]}"; do wait "$p" || fail=1; done
echo "typechecked $checked files across $JOBS workers"
exit $fail
