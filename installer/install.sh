#!/bin/sh
# Quill OS installer for Apple Silicon Macs, run from the folder it came in.
#
#   ./install.sh            check the folder, then start the installer
#   ./install.sh --verify   only check the folder; changes nothing
#   ./install.sh --preflight  --verify, then check this Mac (chip, macOS, free
#                           space, backup); only reads, changes nothing
#
# This is the same bootstrap Fedora Asahi Remix uses, pointed at files in this
# folder instead of at a web server. The installer it starts is Asahi's own.
# SPDX-License-Identifier: MIT

quill_main() {
set -e

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

verify_only=0
preflight=0
case ${1:-} in
    --verify) verify_only=1; shift ;;
    --preflight) verify_only=1; preflight=1; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; return 0 ;;
esac

# Absolute path of this folder, whatever it is called.
DIR=$(cd "$(dirname "$0")" && pwd -P)

if [ ! -e /System ]; then
    echo "This installer runs on a Mac. It was started on another system." >&2
    return 1
fi

# curl needs to read file:// URLs, the way the upstream bootstrap does.
if ! curl --no-progress-meter -o /dev/null file:///dev/null 2>/dev/null; then
    echo "This Mac's curl cannot read local files (file:///). The installer cannot continue." >&2
    return 1
fi

echo
echo "Checking the files in $DIR ..."
cd "$DIR"
if [ ! -f SHA256SUMS ]; then
    echo "SHA256SUMS is missing. The folder is incomplete." >&2
    return 1
fi
if ! shasum -a 256 -c SHA256SUMS >/dev/null 2>&1; then
    echo "The files do not match SHA256SUMS: something is damaged or was changed." >&2
    echo "Run  shasum -a 256 -c SHA256SUMS  to see which, and copy the folder again." >&2
    return 1
fi
echo "  All files match SHA256SUMS."

# --preflight: read this Mac's state and say whether the install fits. It only
# reads (sysctl, sw_vers, df, fdesetup, pmset, defaults read); it writes nothing.
pf_block=0
pf_warn=0
pf_ok()    { printf '  ok     %s\n' "$1"; }
pf_info()  { printf '  info   %s\n' "$1"; }
pf_warnf() { printf '  WARN   %s\n' "$1"; pf_warn=$((pf_warn + 1)); }
pf_blockf(){ printf '  BLOCK  %s\n' "$1"; pf_block=$((pf_block + 1)); }
gb() { # BYTES -> "12.3 GB" (decimal, one place)
    echo "$1" | awk '{ printf "%.1f GB", $1 / 1000000000 }'
}

preflight_checks() {
    echo
    echo "Checking this Mac (read-only) ..."

    brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
    gen=$(printf '%s' "$brand" | sed -n 's/^Apple M\([0-9][0-9]*\).*/\1/p')
    if [ -z "$gen" ]; then
        pf_blockf "chip: ${brand:-unknown}. The installer needs an Apple Silicon Mac."
    elif [ "$gen" -le 2 ]; then
        pf_ok "chip: $brand (supported by Asahi Linux)"
    else
        pf_blockf "chip: $brand. Asahi Linux does not support this chip yet. Use the virtual machine instead (docs/vm.md)."
    fi

    ver=$(sw_vers -productVersion 2>/dev/null || true)
    major=${ver%%.*}
    case $major in
        ''|*[!0-9]*) pf_warnf "macOS version unknown" ;;
        *)
            if [ "$major" -lt 13 ]; then
                pf_blockf "macOS $ver is too old. Update to macOS 13.5 or later first."
            elif [ "$major" -gt 15 ]; then
                pf_warnf "macOS $ver is newer than this installer has been checked against. It may refuse or fail; the virtual machine is the safer route."
            else
                pf_ok "macOS $ver"
            fi ;;
    esac

    free_kb=$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $4}')
    case $free_kb in ''|*[!0-9]*) free_kb=$(df -k / | awk 'NR==2 {print $4}') ;; esac
    free=$((free_kb * 1024))
    stub=3000000000
    echo "  info   free space on the Mac's disk: $(gb "$free"); macOS's recovery stub adds about $(gb $stub)"
    fits=0
    # one line per system offered: its partitions, summed
    sizes=$(awk '
        { match($0, /^ */); ind = RLENGTH }
        /"name":/ && ind == 12 { n = $0; sub(/^ *"name": *"/, "", n); sub(/".*$/, "", n); next }
        /"size": *"[0-9]+B"/ { v = $0; gsub(/[^0-9]/, "", v); if (!(n in sum)) order[++c] = n; sum[n] += v }
        END { for (i = 1; i <= c; i++) print sum[order[i]] "|" order[i] }' installer_data.json)
    old_ifs=$IFS
    IFS='
'
    for line in $sizes; do
        need=${line%%|*}; os=${line#*|}
        need=$((need + stub))
        left=$((free - need))
        if [ "$left" -lt 0 ]; then
            pf_warnf "$os needs $(gb "$need"); only $(gb "$free") is free, so it cannot be installed"
        elif [ "$left" -lt 20000000000 ]; then
            fits=1
            pf_warnf "$os needs $(gb "$need"); macOS would be left with only $(gb "$left") free"
        else
            fits=1
            pf_ok "$os needs $(gb "$need"); macOS would keep $(gb "$left") free"
        fi
    done
    IFS=$old_ifs
    [ "$fits" = 1 ] || pf_blockf "none of the systems offered fits in the free space"

    fv=$(fdesetup status 2>/dev/null | head -n 1)
    [ -n "$fv" ] && pf_info "$fv The installer will ask for your macOS password."

    if pmset -g batt 2>/dev/null | grep -q "Battery Power"; then
        pf_warnf "running on battery. Plug in before installing."
    else
        pf_ok "on mains power (or no battery)"
    fi

    last=$(defaults read /Library/Preferences/com.apple.TimeMachine 2>/dev/null \
        | awk '/SnapshotDates/ {f=1; next} f && /\)/ {exit} f && /"/ {d=$0} END {gsub(/^ *"|".*$/, "", d); print d}')
    if [ -n "$last" ]; then
        pf_info "last Time Machine backup: $last. Make a fresh one first."
    else
        pf_warnf "no Time Machine backup found (or it could not be read). Back up before installing."
    fi
}

for f in latest installer_data.json; do
    [ -f "$f" ] || { echo "Missing $f" >&2; return 1; }
done
PKG_VER=$(tr -d '\r\n' < latest)
if [ ! -f "installer-$PKG_VER.tar.gz" ]; then
    echo "Missing installer-$PKG_VER.tar.gz" >&2
    return 1
fi
if command -v plutil >/dev/null 2>&1; then
    plutil -convert xml1 -o /dev/null installer_data.json 2>/dev/null || { echo "installer_data.json is not valid." >&2; return 1; }
fi
# every package named in installer_data.json must be here
for pkg in $(sed -n 's/.*"package": *"\([^"]*\)".*/\1/p' installer_data.json); do
    [ -f "os/$pkg" ] || { echo "Missing os/$pkg" >&2; return 1; }
done
echo "  Installer $PKG_VER and the OS packages are present."

if [ "$preflight" = 1 ]; then
    preflight_checks
    echo
    if [ "$pf_block" -gt 0 ]; then
        echo "NOT READY: $pf_block blocking problem(s) above. Nothing was installed or changed."
        return 1
    elif [ "$pf_warn" -gt 0 ]; then
        echo "READY, with $pf_warn warning(s) above. Nothing was installed or changed."
    else
        echo "READY. Nothing was installed or changed."
    fi
    return 0
fi

if [ "$verify_only" = 1 ]; then
    echo "Verified. Nothing was installed."
    return 0
fi

cat <<WARN

Quill OS will be installed next to macOS on this Mac. The installer shrinks the
macOS partition to make room, which changes the disk's partition table.
Back up your data first. If it is interrupted, macOS can usually be recovered,
but that is not guaranteed.

Nothing in this folder has been tested on real Apple Silicon hardware yet.
WARN
printf 'Continue? [y/N] '
read -r answer </dev/tty || answer=n
case $answer in y|Y|yes|YES) ;; *) echo "Cancelled."; return 1 ;; esac

# file:// needs the path percent-encoded; REPO_BASE is a plain path.
url_dir=$(printf '%s' "$DIR" | sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/#/%23/g' -e 's/?/%3F/g')
export VERSION_FLAG="file://$url_dir/latest"
export INSTALLER_BASE="file://$url_dir"
export INSTALLER_DATA="file://$url_dir/installer_data.json"
export REPO_BASE="$DIR"
export DISTRO="Quill OS"
export DISTRO_DOCS="$DIR/README.txt"
# REPORT and REPORT_TAG stay unset: the installer then sends no statistics.

TMP=${QUILL_INSTALL_TMP:-/tmp/asahi-install}

echo
echo "Bootstrapping installer:"

if [ -e "$TMP" ]; then
    mv "$TMP" "$TMP-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$TMP"
cd "$TMP"

echo "  Checking version..."
PKG_VER="$(curl --no-progress-meter -L "$VERSION_FLAG")"
echo "  Version: $PKG_VER"
PKG="installer-$PKG_VER.tar.gz"

echo "  Copying..."
curl --no-progress-meter -L -o "$PKG" "$INSTALLER_BASE/$PKG"
curl --no-progress-meter -L -o installer_data.json "$INSTALLER_DATA"

echo "  Extracting..."
tar xf "$PKG"

echo "  Initializing..."
echo

if [ "$USER" != "root" ]; then
    echo "The installer needs to run as root."
    echo "Please enter your sudo password if prompted."
    exec caffeinate -dis sudo -E ./install.sh "$@"
else
    exec caffeinate -dis ./install.sh "$@"
fi
}

# The whole script is defined above before anything runs, so a truncated copy
# fails to parse instead of running half of it.
quill_main "$@"
exit $?
