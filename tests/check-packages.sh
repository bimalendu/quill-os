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

case "$profile" in
    *VM*)
        # A generic aarch64 UEFI VM: Fedora's own kernel and guest tools, nothing from Asahi.
        for p in kernel-core grub2-efi-aa64 qemu-guest-agent spice-vdagent mesa-dri-drivers; do must "$p"; done
        for p in kernel-16k-core asahi-platform-metapackage asahi-audio speakersafetyd tiny-dfr m1n1 \
                 update-m1n1 dracut-asahi asahi-fwupdate alsa-ucm-asahi asahi-repos \
                 fedora-asahi-remix-scripts muvm fex-emu; do must_not "$p"; done ;;
    *)
        # Apple Silicon: the Asahi hardware stack. Quill never drops these.
        for p in kernel-16k-core asahi-platform-metapackage asahi-audio speakersafetyd \
                 tiny-dfr m1n1 update-m1n1 mesa-dri-drivers \
                 alsa-ucm-asahi dracut-asahi; do must "$p"; done ;;
esac

# Quill's own branding packages, and none of the Fedora or Asahi ones they replace.
for p in quill-release-common quill-snapshots snapper libdnf5-plugin-actions; do must "$p"; done
for p in fedora-logos fedora-release-common fedora-release-kde fedora-release-identity-kde \
         fedora-asahi-remix-release-common fedora-asahi-remix-release-kde-desktop \
         fedora-bookmarks abrt abrt-desktop libreport-fedora mediawriter \
         NetworkManager-config-connectivity-fedora; do must_not "$p"; done

# Packages removed on purpose.
for p in akonadi-server kdepim-runtime kmail kontact korganizer kaddressbook \
         akregator kleopatra libreoffice-core libreoffice-writer elisa-player \
         kde-connect kmahjongg kmines kpat krusader ktorrent neochat krdc \
         gnome-shell gnome-session; do must_not "$p"; done

case "$profile" in
    *KDE*)
        for p in plasma-desktop plasma-setup plasma-login-manager dolphin konsole kwrite okular \
                 kcalc gwenview firefox quill-release-kde-desktop quill-release-identity-kde-desktop \
                 quill-backgrounds-kde quill-plasma-theme quill-logos quill-no-ai quill-setup \
                 quill-updates mesa-vulkan-drivers; do must "$p"; done
        for p in f44-backgrounds-kde f44-backgrounds-base desktop-backgrounds-kde \
                 breeze-icon-theme-fedora plasma-welcome-fedora kde-settings-plasmalogin; do
            must_not "$p"; done ;;
esac

n=$(wc -l < "$pk" | tr -d ' ')
echo "packages: $n"
exit "$fail"
