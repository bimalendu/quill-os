#!/bin/sh
# Assert the on-disk branding of a built image. Run inside the builder
# container with the image's root filesystem mounted.
# Usage: check-branding.sh <root> [profile]
root="$1"
profile="${2:-Workstation-KDE}"
[ -f "$root/etc/os-release" ] || [ -L "$root/etc/os-release" ] || { echo "no os-release under $root"; exit 2; }
fail=0

ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
eq()  { [ "$2" = "$3" ] && ok "$1 = $3" || bad "$1: got '$2', want '$3'"; }

osr="$root/usr/lib/os-release"
get() { sed -n "s/^$1=//p" "$osr" | tr -d '"'; }

eq "os-release NAME"    "$(get NAME)"    "Quill OS"
eq "os-release ID"      "$(get ID)"      "quill"
eq "os-release ID_LIKE" "$(get ID_LIKE)" "fedora"
eq "os-release LOGO"    "$(get LOGO)"    "quill-logo-icon"
grep -q "^REDHAT_" "$osr" && bad "os-release routes bugs to Red Hat (REDHAT_* fields)" || ok "no REDHAT_* fields in os-release"
grep -qi "fedora asahi remix\|fedora linux" "$osr" && bad "os-release still mentions Fedora" || ok "os-release does not mention Fedora"
[ -f "$root/usr/share/icons/hicolor/48x48/places/start-here.png" ] && ok "start-here icon present" || bad "start-here icon missing"
[ -f "$root/usr/share/pixmaps/system-logo-white.png" ] && ok "system-logo-white.png present" || bad "system-logo-white.png missing"

# Nothing may phone home to Fedora by default.
if grep -rIl "fedoraproject.org" "$root/etc/NetworkManager" "$root/usr/lib/NetworkManager" 2>/dev/null | grep -q .; then
    bad "NetworkManager config still contacts fedoraproject.org"
else
    ok "NetworkManager config does not contact fedoraproject.org"
fi
[ -e "$root/etc/libreport/workflows.d/report_fedora.conf" ] \
    && bad "Fedora crash-report workflow still installed" || ok "no Fedora crash-report workflow"

# No Fedora logo files may remain.
n=$(find "$root/usr/share" \( -iname 'fedora-logo*' -o -iname 'fedora_logo*' -o -iname 'fedora-gdm-logo*' \) 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = 0 ] && ok "no fedora-logo* files" || { bad "$n fedora-logo* files remain:"; find "$root/usr/share" \( -iname 'fedora-logo*' -o -iname 'fedora_logo*' \) | head -5; }

case "$profile" in
    *KDE*)
        grep -q "^LookAndFeelPackage=org.quill.desktop" "$root/etc/xdg/kdeglobals" \
            && ok "default look and feel is org.quill.desktop" || bad "default look and feel is not org.quill.desktop"
        grep -q "wallpapers/Quill" "$root/usr/lib/plasmalogin/defaults.conf" \
            && ok "login screen wallpaper is Quill" || bad "login screen wallpaper is not Quill"
        [ -f "$root/usr/share/wallpapers/Quill/metadata.json" ] && ok "Quill wallpaper installed" || bad "Quill wallpaper missing"
        [ -f "$root/usr/share/color-schemes/QuillLight.colors" ] && ok "Quill colour schemes installed" || bad "Quill colour scheme missing" ;;
esac

exit "$fail"
