#!/bin/sh
# Static boot-chain checks for the generic aarch64 UEFI VM image. Nothing here
# boots the image; it checks the things that most often stop one booting.
# Runs in the builder container with the image's .raw and .qcow2 mounted at /image.
# Usage: check-vm.sh <image dir>
dir="$1"
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
has() { [ -e "$1" ] || [ -L "$1" ]; }

raw=$(ls "$dir"/*.raw 2>/dev/null | head -1); qcow=$(ls "$dir"/*.qcow2 2>/dev/null | head -1)
[ -n "$raw" ] && [ -n "$qcow" ] || { echo "need both a .raw and a .qcow2 in $dir"; exit 2; }

# --- the qcow2 is what users boot: it must be sound and match the raw image
[ "$(qemu-img info "$qcow" | sed -n 's/^file format: //p')" = qcow2 ] && ok "qcow2 has the right format" || bad "qcow2 format"
qemu-img check "$qcow" >/dev/null 2>&1 && ok "qemu-img check: qcow2 is consistent" || bad "qemu-img check failed"
qemu-img compare -f raw -F qcow2 "$raw" "$qcow" 2>&1 | grep -q "identical" \
    && ok "qcow2 content is identical to the checked raw image" || bad "qcow2 differs from the raw image"

d=$(losetup -P --sector-size 512 -f --show "$raw"); sleep 1
mkdir -p /m /esp /bt
mount -o ro,subvol=root "${d}p3" /m; mount -o ro "${d}p1" /esp; mount -o ro "${d}p2" /bt
cleanup() { umount /bt /esp /m 2>/dev/null; losetup -d "$d" 2>/dev/null; }
trap cleanup EXIT

# --- UEFI: the firmware finds the removable-media path with no NVRAM entry
has /esp/EFI/BOOT/BOOTAA64.EFI && ok "EFI/BOOT/BOOTAA64.EFI exists (firmware fallback path)" || bad "no EFI/BOOT/BOOTAA64.EFI"
has /esp/EFI/fedora/shimaa64.efi && has /esp/EFI/fedora/grubaa64.efi && ok "shim and GRUB are on the ESP" || bad "shim or GRUB missing from the ESP"
has /esp/m1n1 && bad "an Apple m1n1 directory is on the ESP" || ok "no m1n1 on the ESP"

# --- the boot entry: stock kernel, files exist, root UUID is the real one
entry=$(ls /bt/loader/entries/*.conf 2>/dev/null | head -1)
[ -n "$entry" ] && ok "a BLS boot entry exists" || bad "no BLS boot entry"
kern=$(sed -n 's/^linux //p' "$entry"); initrd=$(sed -n 's/^initrd \([^ ]*\).*/\1/p' "$entry")
has "/bt$kern" && has "/bt$initrd" && ok "kernel and initramfs named by the entry exist" || bad "entry names a missing kernel or initramfs"
echo "$kern" | grep -q 16k && bad "boot entry uses an Asahi 16k kernel" || ok "boot entry uses the stock (4k page) kernel"
grep -q '^title Quill OS' "$entry" && ok "boot entry is titled Quill OS" || bad "boot entry title is not Quill OS"
rootuuid=$(blkid -s UUID -o value "${d}p3")
grep -q "root=UUID=$rootuuid" "$entry" && ok "boot entry root UUID matches the root partition" || bad "boot entry root UUID is wrong"
for dev in "${d}p1" "${d}p2" "${d}p3"; do
    u=$(blkid -s UUID -o value "$dev"); grep -q "UUID=$u" /m/etc/fstab || bad "fstab has no entry for $dev ($u)"
done; ok "every partition's UUID is in /etc/fstab"
n=$(ls /m/usr/lib/modules | wc -l | tr -d ' ')
[ "$n" = 1 ] && ! ls /m/usr/lib/modules | grep -q 16k && ok "exactly one kernel installed, not an Asahi one" || bad "unexpected kernels: $(ls /m/usr/lib/modules | tr '\n' ' ')"

# --- drivers needed to find the disk and mount root: built in, or in the initramfs
lsinitrd "/bt$initrd" > /tmp/initrd.txt 2>/dev/null
need() { # <kconfig symbol> <module name>
    v=$(sed -n "s/^CONFIG_$1=//p" /bt/config-* | head -1)
    case "$v" in
        y) ok "kernel has $1 built in" ;;
        m) grep -q "/$2\.ko" /tmp/initrd.txt && ok "$1 is a module and is in the initramfs" || bad "$1 is a module missing from the initramfs" ;;
        *) bad "kernel has no $1" ;;
    esac
}
need VIRTIO_BLK virtio_blk
need VIRTIO_PCI virtio_pci
need BTRFS_FS btrfs
need EXT4_FS ext4
need VFAT_FS vfat

# --- services that bring up a graphical login and the guest tools
[ "$(readlink /m/etc/systemd/system/default.target)" = /usr/lib/systemd/system/graphical.target ] && ok "default target is graphical" || bad "default target is not graphical"
readlink /m/etc/systemd/system/display-manager.service | grep -q plasmalogin && ok "display manager is Plasma Login Manager" || bad "display manager is not plasmalogin"
for u in plasma-setup qemu-guest-agent NetworkManager; do
    find /m/etc/systemd/system -name "$u.service" | grep -q . && ok "$u is enabled" || bad "$u is not enabled"
done
grep -rqh '^enable spice-vdagentd.service' /m/usr/lib/systemd/system-preset/ && ok "spice-vdagentd is enabled by preset (applied on first boot)" || bad "spice-vdagentd is not preset-enabled"
has /m/etc/xdg/autostart/spice-vdagent.desktop && ok "spice-vdagent user agent autostarts" || bad "no spice-vdagent autostart"
grep -q uninitialized /m/etc/machine-id && ok "machine-id is uninitialized, so first-boot presets and setup run" || bad "machine-id is already set"
exit "$fail"
