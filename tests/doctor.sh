#!/bin/sh
# Check the host can build Quill OS. Usage: doctor.sh <podman-machine-name>
machine="${1:-quill-build}"
fail=0

check() {
    if command -v "$1" >/dev/null 2>&1; then
        printf 'ok    %s\n' "$1"
    else
        printf 'MISS  %s (%s)\n' "$1" "$2"
        fail=1
    fi
}

check podman "brew install podman"
check git "brew install git"
check make "xcode-select --install"
check curl "preinstalled on macOS"

if [ "$(uname -m)" = "arm64" ]; then
    echo "ok    host is arm64 (native aarch64 containers, no emulation)"
else
    echo "WARN  host is $(uname -m): aarch64 builds will be emulated and slow"
fi

if podman machine inspect "$machine" >/dev/null 2>&1; then
    rootful=$(podman machine inspect "$machine" --format '{{.Rootful}}')
    mem=$(podman machine inspect "$machine" --format '{{.Resources.Memory}}')
    echo "ok    podman machine '$machine' exists (rootful=$rootful, ${mem} MiB)"
    [ "$rootful" = "true" ] || { echo "FAIL  '$machine' must be rootful"; fail=1; }
else
    echo "MISS  podman machine '$machine' (run: make machine)"
    fail=1
fi

exit "$fail"
