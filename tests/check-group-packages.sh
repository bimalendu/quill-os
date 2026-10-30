#!/bin/sh
# Check that every package and Flatpak named by the Quill Setup groups exists
# for this architecture. Needs network. Runs in the builder container.
# Usage: check-group-packages.sh <dir with rpms and flatpaks lists from check-groups.py --dump>
d="$1"
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
arch=$(uname -m)
while IFS='|' read -r name _; do
    [ -n "$name" ] || continue
    if dnf5 -q repoquery --available --arch "$arch,noarch" "$name" 2>/dev/null | grep -q .; then
        ok "rpm $name exists for $arch"
    else
        bad "rpm $name is not available for $arch"
    fi
done < "$d/rpms"
if [ -s "$d/flatpaks" ]; then
    flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
    while read -r id; do
        [ -n "$id" ] || continue
        if flatpak remote-info --system flathub "$id" 2>/dev/null | grep -q "Arch: $arch"; then
            ok "flatpak $id exists for $arch"
        else
            bad "flatpak $id has no $arch build on Flathub"
        fi
    done < "$d/flatpaks"
fi
exit "$fail"
