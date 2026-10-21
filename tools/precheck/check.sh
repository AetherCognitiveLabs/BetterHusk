#!/bin/bash
# Syntax-checks the native sources the app target compiles, against the real
# iPhone SDK. The error class this catches (C/ObjC compile breakage) used to
# surface 40-110 minutes into the IPA build; here it fails in ~2 minutes.
#
# tools/precheck/include holds stub headers for what the iOS SDK lacks
# (CommonCrypto, a few POSIX paths) -- last in -I order so real SDK and in-tree
# headers always win.
set -uo pipefail
cd "$(dirname "$0")/../.."

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
INC=(
  "-I$PWD/src/app/Husk"
  "-I$PWD/src/translation-layer"
  "-I$PWD/src/translation-layer-next"
  "-I$PWD/src/ios-jit"
  "-I$PWD/tools/precheck/include"
)
COMMON=(-fsyntax-only -isysroot "$SDK" -target arm64-apple-ios15.5)

fail=0
checked=0
skipped=0
while IFS= read -r f; do
  # Files integrate_husk.sh injects into the QEMU tree include QEMU/glib/slirp
  # headers that do not exist until the dependency build -- they are verified
  # by the qemurebuild step there, not here.
  if grep -qE '#[[:space:]]*include[[:space:]]*[<"](qemu|glib|slirp|qapi|sysemu|ui|hw|exec|migration)' "$f"; then
    skipped=$((skipped + 1))
    continue
  fi
  case "$f" in
    *.m|*.mm) lang=(-x objective-c -fobjc-arc -fmodules) ;;
    *) lang=(-x c) ;;
  esac
  if ! clang "${COMMON[@]}" "${lang[@]}" "${INC[@]}" "$f"; then
    echo "::error file=$f::native precheck failed"
    fail=1
  fi
  checked=$((checked + 1))
done < <(git ls-files src/app src/translation-layer src/translation-layer-next src/ios-jit \
         | grep -E '\.(c|m|mm)$' | grep -v '^src/rppairing-ios/')

echo "precheck: $checked native files checked, $skipped skipped (QEMU-side)"
exit $fail
