#!/bin/sh
# Quill OS installer for Apple Silicon Macs, run from the folder it came in.
#
#   ./install.sh            check the folder, then start the installer
#   ./install.sh --verify   only check the folder; changes nothing
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
case ${1:-} in
    --verify) verify_only=1; shift ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; return 0 ;;
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

for f in latest installer_data.json; do
    [ -f "$f" ] || { echo "Missing $f" >&2; return 1; }
done
PKG_VER=$(tr -d '\r\n' < latest)
if [ ! -f "installer-$PKG_VER.tar.gz" ]; then
    echo "Missing installer-$PKG_VER.tar.gz" >&2
    return 1
fi
if command -v plutil >/dev/null 2>&1; then
    plutil -lint installer_data.json >/dev/null || { echo "installer_data.json is not valid." >&2; return 1; }
fi
# every package named in installer_data.json must be here
for pkg in $(sed -n 's/.*"package": *"\([^"]*\)".*/\1/p' installer_data.json); do
    [ -f "os/$pkg" ] || { echo "Missing os/$pkg" >&2; return 1; }
done
echo "  Installer $PKG_VER and the OS packages are present."

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
