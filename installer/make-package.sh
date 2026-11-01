#!/bin/sh
# Package one raw Quill OS image as an asahi-installer OS package.
#
#   make-package.sh KEY "DISPLAY NAME" IMAGE.raw OUTDIR DATE [EXTRAS_FILE]
#
# Writes OUTDIR/os/quill-<release>-<KEY>-<DATE>.zip and OUTDIR/os/<same>.json
# (one os_list entry). Adapted from kiwi/make-asahi-installer-package.sh, which
# is the unchanged upstream copy. Differences: Quill name and boot icon, local
# paths only, firmware list from supported_fw.json, no logs zip, no raw.zst.
# Runs in the builder container; the 4 KiB-sector images are Apple Silicon ones.
set -eu

fail() { echo "make-package: $*" >&2; exit 1; }

[ $# -ge 5 ] || fail "usage: $0 KEY NAME IMAGE OUTDIR DATE [EXTRAS_FILE]"
key=$1 name=$2 image=$3 outdir=$4 date=$5 extras_file=${6:-}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
release=${FEDORA_RELEASE:-44}

[ -r "$image" ] || fail "$image does not exist or cannot be read"
for cmd in 7z awk dd fdisk file stat rsvg-convert python3; do
    command -v "$cmd" >/dev/null || fail "missing command: $cmd"
done

package="quill-${release}-${key}-${date}"
mkdir -p "$outdir/os"
[ ! -e "$outdir/os/$package.zip" ] || fail "$outdir/os/$package.zip already exists"

# The work area is next to the output: it holds a copy of the whole image.
workdir=$(mktemp -d "$outdir/.work.XXXXXX")
trap 'rm -rf "$workdir"' EXIT
imagename=$(basename "$image")

# Cut the three partitions out of the image (4096-byte sectors).
eval "$(fdisk -Lnever -lu -b 4096 "$image" | awk -v img="$image" -v w="$workdir" \
    '$1 ~ ("^" img "[0-9]+$") { printf "dd if=\"%s\" of=\"%s/part%s\" skip=%s count=%s bs=4096 status=none\n", img, w, substr($1, length(img) + 1), $2, $4 }')"
for n in 1 2 3; do [ -s "$workdir/part$n" ] || fail "partition $n not found in $imagename"; done

pkg="$workdir/package"
mkdir -p "$pkg/esp"
7z x -bso0 -bsp0 -o"$pkg/esp" "$workdir/part1"
mv "$workdir/part2" "$pkg/boot.img"
mv "$workdir/part3" "$pkg/root.img"

# Fix up grub in the ESP: https://bugzilla.redhat.com/show_bug.cgi?id=2235692
# The signed shim still loads EFI/fedora, so that directory stays.
sed -i 's:source :configfile :' "$pkg/esp/EFI/fedora/grub.cfg"
rm "$pkg/esp/EFI/BOOT/grubaa64.efi" "$pkg/esp/EFI/BOOT/grub.cfg"
[ -f "$pkg/esp/m1n1/boot.bin" ] || fail "the ESP has no m1n1/boot.bin"

esp_volume_id=$(file "$workdir/part1" | awk -v 'RS=,' '/serial number/ { print $3 }')
[ -n "$esp_volume_id" ] || fail "could not read the ESP volume id"
esp_size=$(stat -c %s "$workdir/part1")
boot_size=$(stat -c %s "$pkg/boot.img")
root_size=$(stat -c %s "$pkg/root.img")

# Boot picker icon, drawn from the Quill mark.
for s in 128 256 512 1024; do
    rsvg-convert -w $s -h $s "$repo/packages/quill-logos/quill-mark.svg" -o "$workdir/icon$s.png"
done
python3 -I "$here/make-icns.py" "$pkg/quill.icns" "$workdir"/icon128.png "$workdir"/icon256.png "$workdir"/icon512.png "$workdir"/icon1024.png

# Zip it (zip64 is automatic) under a temporary name so a failure leaves no half file.
( cd "$pkg" && 7z a -bso0 -bsp0 -tzip -mx=3 -r "$outdir/os/$package.zip.part" . )
mv "$outdir/os/$package.zip.part" "$outdir/os/$package.zip"

if [ -n "$extras_file" ] && [ -s "$extras_file" ]; then
    extras=$(cat "$extras_file")
else
    extras="[]"
fi
fw=$(cat "$here/supported_fw.json")

cat > "$outdir/os/$package.json" <<JSON
{
    "name": "$name",
    "default_os_name": "Quill OS",
    "boot_object": "m1n1.bin",
    "next_object": "m1n1/boot.bin",
    "package": "$package.zip",
    "icon": "quill.icns",
    "supported_fw": $fw,
    "extras": $extras,
    "partitions": [
        {
            "name": "EFI",
            "type": "EFI",
            "size": "${esp_size}B",
            "format": "fat",
            "volume_id": "$esp_volume_id",
            "copy_firmware": true,
            "copy_installer_data": true,
            "source": "esp"
        },
        {
            "name": "Boot",
            "type": "Linux",
            "size": "${boot_size}B",
            "image": "boot.img"
        },
        {
            "name": "Root",
            "type": "Linux",
            "size": "${root_size}B",
            "expand": true,
            "image": "root.img"
        }
    ]
}
JSON
echo "make-package: wrote $outdir/os/$package.zip"
