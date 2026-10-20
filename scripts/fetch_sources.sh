#!/bin/bash
# Download + unpack every Husk dependency into third_party/sources and third_party/build.
set -u
HUSK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$HUSK_ROOT/scripts/sources.sh"
DL="$HUSK_ROOT/third_party/sources"
SRC="$HUSK_ROOT/third_party/build"
mkdir -p "$DL" "$SRC"

fetch() {
    local url="$1" file="$DL/$(basename "$1")"
    if [ -s "$file" ]; then echo "[skip] $(basename "$file")"; return 0; fi
    echo "[get ] $(basename "$file")"
    curl -fL --retry 3 --retry-delay 5 -o "$file.part" "$url" || { echo "[FAIL] $url"; return 1; }
    mv "$file.part" "$file"
}

unpack() {
    local file="$DL/$(basename "$1")" stamp
    stamp="$SRC/.unpacked-$(basename "$file")"
    [ -f "$stamp" ] && { echo "[skip] unpack $(basename "$file")"; return 0; }
    echo "[tar ] $(basename "$file")"
    tar -xf "$file" -C "$SRC" || return 1
    touch "$stamp"
}

rc=0
for u in "$FFI_SRC" "$ICONV_SRC" "$GETTEXT_SRC" "$GLIB_SRC" "$PIXMAN_SRC" "$SLIRP_SRC" "$QEMU_SRC"; do
    fetch "$u" || rc=1
done
for u in "$FFI_SRC" "$ICONV_SRC" "$GETTEXT_SRC" "$GLIB_SRC" "$PIXMAN_SRC" "$SLIRP_SRC" "$QEMU_SRC"; do
    unpack "$u" || rc=1
done

# A git clone is one TCP connection with no retry built in, and a flaky runner
# turns that into a failed 20-minute build. The tarballs above retry three
# times; these get the same courtesy, with the half-cloned directory dropped
# between attempts so a dead clone cannot look like a finished one.
clone_pinned() {
    local repo="$1" commit="$2" dest="$3" name="$4"
    if [ -d "$dest" ]; then echo "[skip] $name"; return 0; fi
    local attempt
    for attempt in 1 2 3; do
        echo "[git ] $name (attempt $attempt)"
        if git clone "$repo" "$dest" >/dev/null 2>&1 \
            && git -C "$dest" checkout -q "$commit" 2>/dev/null; then
            return 0
        fi
        rm -rf "$dest"
        sleep $((attempt * 5))
    done
    echo "[FAIL] $name"
    return 1
}

clone_pinned "$LIBUCONTEXT_REPO" "$LIBUCONTEXT_COMMIT" "$SRC/libucontext" libucontext || rc=1
clone_pinned "$HYPERVISOR_REPO" "$HYPERVISOR_COMMIT" "$SRC/Hypervisor" Hypervisor || rc=1

echo "--- result rc=$rc ---"
ls -1 "$SRC" | grep -v '^\.' 
exit $rc
