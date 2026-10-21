#!/bin/bash
# Typechecks the app target's Swift sources the way the Xcode build sees them:
# one module, the ObjC bridging header, the iPhone SDK. Catches the type-error
# class ("l10n pass" breakage) without the 40+ minute dependency build.
set -euo pipefail
cd "$(dirname "$0")/../.."

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
FILES="$(git ls-files 'src/app/Husk' 'src/app/Shared' | grep '\.swift$'; git ls-files 'src/app/HuskJITHelper/HuskJITMessages.swift')"

# shellcheck disable=SC2086
xcrun --sdk iphoneos swiftc -typecheck \
  -target arm64-apple-ios15.5 \
  -sdk "$SDK" \
  -module-name Husk \
  -parse-as-library \
  -import-objc-header src/app/Husk/HuskBridge.h \
  -I src/app/Husk \
  -I src/ios-jit \
  -I src/translation-layer \
  -I src/translation-layer-next \
  -idirafter tools/precheck/include \
  $FILES
