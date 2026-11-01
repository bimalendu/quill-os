#!/bin/sh
# Assemble the self-contained Quill OS installer folder. Runs in the builder
# container with the out volume mounted at /out (read-write).
#
#   assemble.sh build DATE     build /out/installer/quill-os-<release>-<DATE>/
#   assemble.sh refresh [DIR]  re-copy install.sh and README.txt into an existing
#                              folder (the newest if no DIR) and redo SHA256SUMS
#   assemble.sh lock           print installer.lock for upstream's newest installer
set -eu

fail() { echo "assemble: $*" >&2; exit 1; }

here=$(cd "$(dirname "$0")" && pwd)
release=${FEDORA_RELEASE:-44}
upstream=https://fedora-asahi-remix.org/installer
# QUILL_INSTALLER_OUT and QUILL_LOCK exist so tests can run against scratch copies.
out=${QUILL_INSTALLER_OUT:-/out/installer}
lock=${QUILL_LOCK:-$here/installer.lock}
cache=$out/.cache

fetch_installer() { # VERSION -> path of the cached tarball
    mkdir -p "$cache"
    f=$cache/installer-$1.tar.gz
    if [ ! -s "$f" ]; then
        curl -fsSL -o "$f.part" "$upstream/installer-$1.tar.gz"
        mv "$f.part" "$f"
    fi
    echo "$f"
}

lock_value() { sed -n "s/^$1=//p" "$lock"; }

case ${1:-} in
lock)
    ver=$(curl -fsSL "$upstream/latest" | tr -d '\r\n')
    [ -n "$ver" ] || fail "could not read the upstream version"
    f=$(fetch_installer "$ver")
    echo "version=$ver"
    echo "sha256=$(sha256sum "$f" | awk '{print $1}')"
    ;;
build)
    date=${2:?usage: assemble.sh build DATE}
    ver=$(lock_value version) want=$(lock_value sha256)
    [ -n "$ver" ] && [ -n "$want" ] || fail "installer.lock is incomplete"

    # 1. The pinned installer, checked against the lock before anything is built.
    f=$(fetch_installer "$ver")
    got=$(sha256sum "$f" | awk '{print $1}')
    if [ "$got" != "$want" ]; then
        rm -f "$f"
        fail "installer-$ver.tar.gz has sha256 $got, but installer.lock pins $want"
    fi
    latest=$(curl -fsSL "$upstream/latest" 2>/dev/null | tr -d '\r\n' || true)
    [ -z "$latest" ] || [ "$latest" = "$ver" ] || \
        echo "assemble: note: upstream has installer $latest; Quill pins $ver (make installer-lock to move)"

    dir=$out/quill-os-$release-$date
    [ ! -e "$dir" ] || fail "$dir already exists"
    mkdir -p "$dir"

    # 2. One OS package per profile.
    extras=$(mktemp)
    trap 'rm -f "$extras"' EXIT
    dnf5 -q repoquery --repo=fedora-cisco-openh264 --location mozilla-openh264 openh264 2>/dev/null \
        | sort | awk 'BEGIN { printf "[" } { printf "%s\"%s\"", (NR > 1 ? ", " : ""), $0 } END { print "]" }' > "$extras"
    grep -q 'codecs.fedoraproject.org' "$extras" || { echo "[]" > "$extras"; echo "assemble: note: no openh264 URLs found, extras left empty"; }
    sh "$here/make-package.sh" kde "Quill OS $release with KDE Plasma" \
        /out/Workstation-KDE/Quill-OS.aarch64-0.0.0.raw "$dir" "$date" "$extras"
    sh "$here/make-package.sh" minimal "Quill OS $release Minimal" \
        /out/Minimal/Quill-OS.aarch64-0.0.0.raw "$dir" "$date"

    # 3. installer_data.json from the two per-package entries.
    python3 -I - "$dir" > "$dir/installer_data.json" <<'PY'
import glob, json, sys
d = sys.argv[1]
entries = [json.load(open(p)) for p in sorted(glob.glob(d + "/os/*.json"))]
# KDE first, then Minimal
entries.sort(key=lambda e: "Minimal" in e["name"])
print(json.dumps({"os_list": entries}, indent=4))
PY
    rm -f "$dir"/os/*.json

    # 4. The rest of the folder.
    cp "$f" "$dir/installer-$ver.tar.gz"
    printf '%s\n' "$ver" > "$dir/latest"
    cp "$here/install.sh" "$here/README.txt" "$dir/"
    chmod +x "$dir/install.sh"
    ( cd "$dir" && find . -type f ! -name SHA256SUMS | sort | xargs sha256sum > SHA256SUMS )
    echo "assemble: wrote $dir"
    du -sh "$dir"
    ;;
refresh)
    dir=${2:-$(ls -d "$out"/quill-os-* 2>/dev/null | sort | tail -n 1)}
    [ -n "$dir" ] && [ -d "$dir" ] || fail "no installer folder to refresh (build one first)"
    [ -f "$dir/SHA256SUMS" ] && [ -d "$dir/os" ] || fail "$dir is not an installer folder"
    cp "$here/install.sh" "$here/README.txt" "$dir/"
    chmod +x "$dir/install.sh"
    ( cd "$dir" && find . -type f ! -name SHA256SUMS | sort | xargs sha256sum > SHA256SUMS )
    echo "assemble: refreshed $dir"
    ;;
*)
    fail "usage: assemble.sh build DATE | refresh [DIR] | lock"
    ;;
esac
