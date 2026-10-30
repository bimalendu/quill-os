#!/bin/sh
# Assert what a built image does and does not contain.
# Usage: check-packages.sh <kiwi .packages file> [profile]
# The file's first field per line is the package name (kiwi's %{name}|... format).
pk="$1"
profile="${2:-Workstation-KDE}"
[ -r "$pk" ] || { echo "cannot read packages file: $pk"; exit 2; }
fail=0

have() { cut -d'|' -f1 "$pk" | grep -qx "$1"; }
must()     { have "$1" && printf 'ok    has  %s\n' "$1"   || { printf 'FAIL  missing %s\n' "$1"; fail=1; }; }
must_not() { have "$1" && { printf 'FAIL  unexpected %s\n' "$1"; fail=1; } || printf 'ok    lacks %s\n' "$1"; }

# Asahi hardware stack: Quill never drops these.
for p in kernel-16k-core asahi-platform-metapackage asahi-audio speakersafetyd \
         tiny-dfr m1n1 update-m1n1 mesa-dri-drivers mesa-vulkan-drivers \
         alsa-ucm-asahi dracut-asahi; do must "$p"; done

# Packages removed on purpose.
for p in akonadi-server kmail kontact korganizer kaddressbook akregator \
         libreoffice-core elisa-player kde-connect \
         gnome-shell gnome-session; do must_not "$p"; done

case "$profile" in
    *KDE*)
        for p in plasma-desktop plasma-setup plasma-login-manager dolphin konsole kwrite okular \
                 kcalc gwenview firefox; do must "$p"; done ;;
esac

n=$(wc -l < "$pk" | tr -d ' ')
echo "packages: $n"
exit "$fail"
