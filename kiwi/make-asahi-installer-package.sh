#!/bin/sh

set -eu

fail() {
  echo $* >&2
  exit 1
}

requireCommands() {
  for cmd in $*; do
    if ! command -v $cmd &> /dev/null; then
      fail "Cannot find required command: $cmd"
    fi
  done
}

newlineToJson() {
    first_item=true
    printf '['
    while IFS= read -r line; do
        if [ "$first_item" = false ]; then
            printf ', '
        fi
        printf '"%s"' "$line"
        first_item=false
    done
    printf ']\n'
}

release="$(awk -F'[<>]' '/release-version/ { print $3 }' config.xml)"
if [ -f buildver ]; then
  date="$(cat buildver)"
else
  date=$(date +%Y%m%d%H%m)
fi
image="${1:-outdir/Fedora-Asahi-Remix.aarch64-0.0.0.raw}"
package="${2:-fedora-${release}-${date}}"

[ "$release" = rawhide ] && pretty_release="Rawhide" || pretty_release="$release"

if [ ! -r "$image" ]; then
  fail "$image does not exist or cannot be read!"
fi

if [ -e "$package" ]; then
  fail "$package already exists, aborting"
fi

requireCommands 7z awk cat cp dd fdisk file mkdir mv stat curl

workdir="$(mktemp -dp /var/tmp)"
trap 'rm -rf "$workdir"' EXIT

basedir="$PWD"
imagename="$(basename "$image")"
imagedir="$(dirname "$image")"

# extract filesystems from disk image
pushd "$imagedir" > /dev/null
eval "$(fdisk -Lnever -lu -b 4096 "$imagename" | awk "/^${imagename}/ { printf \"dd if=${imagename} of=${workdir}/%s skip=%s count=%s bs=4096\\n\", \$1, \$2, \$4 }")"
popd > /dev/null

# build package
mkdir -p "${workdir}/package/esp"
7z x -o"${workdir}/package/esp" "${workdir}/${imagename}1"
mv "${workdir}/${imagename}2" "${workdir}/package/boot.img"
mv "${workdir}/${imagename}3" "${workdir}/package/root.img"

# fix up grub in the ESP
# https://bugzilla.redhat.com/show_bug.cgi?id=2235692
sed -i 's:source :configfile :' "${workdir}/package/esp/EFI/fedora/grub.cfg"
rm "${workdir}/package/esp/EFI/BOOT/grubaa64.efi" "${workdir}/package/esp/EFI/BOOT/grub.cfg"

esp_volume_id="$(file "${workdir}/${imagename}1" | awk -v 'RS=,' '/serial number/ { print $3 }')"
esp_size="$(stat -c %s "${workdir}/${imagename}1")"
boot_size="$(stat -c %s "${workdir}/package/boot.img")"
root_size="$(stat -c %s "${workdir}/package/root.img")"

# boot picker icon
if [ ! -f fedora.icns ]; then
  curl -LO https://pagure.io/fedora-logos/blob/master/f/bootloader/fedora.icns
fi
cp -p fedora.icns "${workdir}/package"

pushd "${workdir}/package" > /dev/null
7z a -tzip -r "${basedir}/${package}" .
popd > /dev/null

openh264_rpms="mozilla-openh264 openh264"
if [ "$release" != rawhide -a $release -le 39 ]; then
  openh264_rpms="gstreamer1-plugin-openh264 ${openh264_rpms}"
fi
openh264_urls=$(rpmdistro-repoquery fedora "$release" ${openh264_rpms} --location)

if [ -z "${openh264_urls}" ]; then
  extras="{}"
else
  extras="$(printf '%s\n' "${openh264_urls}" | newlineToJson)"
fi

cat > "${package}.json" <<EOF
{
    "name": "Fedora Linux ${pretty_release}",
    "default_os_name": "Fedora Linux ${pretty_release}",
    "boot_object": "m1n1.bin",
    "next_object": "m1n1/boot.bin",
    "package": "${package}.zip",
    "icon": "fedora.icns",
    "supported_fw": ["12.3", "12.3.1", "13.5"],
    "extras": ${extras},
    "partitions": [
        {
            "name": "EFI",
            "type": "EFI",
            "size": "${esp_size}B",
            "format": "fat",
            "volume_id": "${esp_volume_id}",
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
EOF

cat > installer_data.json <<EOF
{
    "os_list": [
        $(cat "${package}.json")
     ]
}
EOF

# Package up the logs
mkdir -p "${workdir}/logs"
cp -p \
  outdir/build/image-root.log \
  outdir/Fedora-Asahi-Remix.aarch64-0.0.0.changes \
  outdir/Fedora-Asahi-Remix.aarch64-0.0.0.packages \
  outdir/kiwi.result.json \
  "${workdir}/logs/"
pushd "${workdir}/logs" > /dev/null
7z a -tzip -r "${basedir}/${package}.logs.zip" .
popd > /dev/null

# Package up the raw image
zstd -c9 < "${image}" > "${basedir}/${package}.raw.zst"
