#!/bin/bash
# Syntax-checks the native sources the app target compiles, against the real
# iPhone SDK. The error class this catches (C/ObjC compile breakage) used to
# surface 40-110 minutes into the IPA build; here it fails in ~2 minutes.
#
# tools/precheck/include holds stub headers for what the iOS SDK lacks -- it
# goes through -idirafter so real SDK headers always win and a stub can never
# shadow one (a shadowed mach/mach.h or zlib.h poisons the whole Darwin module).
set -uo pipefail
cd "$(dirname "$0")/../.."

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
INC=(
  "-I$PWD/src/app/Husk"
  "-I$PWD/src/translation-layer"
  "-I$PWD/src/translation-layer-next"
  "-I$PWD/src/ios-jit"
  "-idirafter$PWD/tools/precheck/include"
)
COMMON=(-fsyntax-only -isysroot "$SDK" -target arm64-apple-ios15.5)

# Include roots whose headers only exist after the dependency/QEMU build:
# integrate_husk.sh injects those sources into the QEMU tree, where the real
# qemurebuild step verifies them. Checking them here can only produce
# false-positive "file not found" errors.
SKIP_INCLUDE_RE='(qemu|qapi|qom|tcg|sysemu|exec|hw|ui|util|io|net|block|chardev|crypto|monitor|scsi|standard-headers|stubs|target|accel|audio|backends|disas|fpu|gdbstub|migration|replay|softmmu|semihosting|elf|host|nbd|fdt|glib|slirp|pixman|virgl|epoxy|EGL|GLES[0-9]?|vulkan|angle|moltenvk)/'

fail=0
checked=0
skipped=0
while IFS= read -r f; do
  if grep -qE "#[[:space:]]*include[[:space:]]*[<\"]${SKIP_INCLUDE_RE}" "$f"; then
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
