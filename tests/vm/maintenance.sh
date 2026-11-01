#!/bin/sh
# Updates and snapshots, tested in a booted VM. Usage: maintenance.sh IMAGE.qcow2
# Runs in the builder container (make vm-test VM_TEST=maintenance).
#
# QUILL_INSTALL=1: the image predates quill-snapshots/quill-updates; install
# them from /quill-repo (served to the guest over HTTP) and run the first-boot
# setup by hand. Used while developing, before rebuilding the image.
. "$(dirname "$0")/vm.sh"
img=$1
[ -f "$img" ] || { echo "usage: $0 IMAGE.qcow2"; exit 2; }

vm_create "$img" && vm_start || exit 1
trap 'vm_stop; kill $http 2>/dev/null' EXIT
vm_wait || exit 1
vm_ssh 'systemctl is-system-running --wait >/dev/null 2>&1; true'
# TCG is slow: PackageKit's default 45s start timeout is not enough here.
vm_ssh 'mkdir -p /etc/systemd/system/packagekit.service.d; printf "[Service]\nTimeoutStartSec=600\n" > /etc/systemd/system/packagekit.service.d/test.conf; systemctl daemon-reload'

snaps() { vm_ssh 'snapper --csvout --no-headers -c root list --columns number,type,pre-number,description'; }
count() { snaps | wc -l; }

if [ "${QUILL_INSTALL:-0}" = 1 ]; then
    python3 -m http.server --directory /quill-repo 8080 >/dev/null 2>&1 & http=$!
    sleep 1
    vm_log "installing quill-snapshots and quill-updates from the local repo"
    vm_ssh 'dnf -y -q --repofrompath=quill,http://10.0.2.2:8080 --setopt=quill.gpgkey=http://10.0.2.2:8080/RPM-GPG-KEY-quill-dev \
            install quill-snapshots quill-updates && systemctl start quill-snapshots-setup.service' || { fail "install"; exit 1; }
fi

echo "--- setup"
check "snapper config for / exists"           'test -f /etc/snapper/configs/root'
check "/.snapshots is a btrfs subvolume"      'btrfs subvolume show /.snapshots >/dev/null'
check "a First boot snapshot exists"          'snapper --csvout --no-headers -c root list --columns description | grep -qx "First boot"'
check "no timeline snapshots"                 'grep -qx "TIMELINE_CREATE=\"no\"" /etc/snapper/configs/root && ! systemctl is-enabled -q snapper-timeline.timer'
check "snapper cleanup timer enabled"         'systemctl is-enabled -q snapper-cleanup.timer'
check "update download timer enabled"         'systemctl is-enabled -q quill-update-download.timer'
check "Discover reminds daily"                'grep -qx RequiredNotificationInterval=86400 /etc/xdg/PlasmaDiscoverUpdates'

echo "--- snapshots around transactions"
# Preconditions: the test packages are absent, and /var/lib/machines is a
# nested subvolume (as on a real system after systemd-nspawn/machinectl use).
check "test packages are not preinstalled"    '! rpm -q cowsay figlet >/dev/null 2>&1'
vm_ssh 'btrfs subvolume show /var/lib/machines >/dev/null 2>&1 || { rmdir /var/lib/machines 2>/dev/null; btrfs subvolume create /var/lib/machines >/dev/null; }'
# The marker is written before the target snapshot, then changed after it.
vm_ssh 'echo before > /etc/quill-rollback-test; echo kept > /var/lib/machines/quill-test'
base=$(vm_ssh 'snapper -c root create --print-number --cleanup-algorithm number --description "before cowsay"')
vm_log "rollback target is snapshot $base"
vm_ssh 'echo after > /etc/quill-rollback-test'
n0=$(count)
check "dnf install works"                     'dnf -y -q install cowsay'
n1=$(count)
[ $((n1 - n0)) -eq 2 ] && pass "dnf transaction made 2 snapshots" || { fail "dnf transaction made $((n1 - n0)) snapshots"; snaps | tail -4; }
snaps | tail -2 | grep -q 'pre,,dnf.*install.*cowsay' && snaps | tail -1 | grep -q '^[0-9]*,post,[0-9]' \
    && pass "the pair is pre/post and names the dnf command" || { fail "pre/post pair"; snaps | tail -2; }

check "PackageKit install works"              'pkcon -y -p install figlet >/dev/null'
n2=$(count)
[ $((n2 - n1)) -eq 2 ] && pass "PackageKit (Discover) transaction made 2 snapshots" || { fail "PackageKit transaction made $((n2 - n1)) snapshots"; snaps | tail -4; }
snaps | tail -1 | grep -q 'post,.*PackageKit' && pass "described as PackageKit (Discover)" || { fail "PackageKit description"; snaps | tail -2; }

# A broken snapper must never block a transaction.
vm_ssh 'chmod -x /usr/bin/snapper'
check "transaction succeeds while snapper is broken" 'dnf -y -q remove figlet'
vm_ssh 'chmod +x /usr/bin/snapper'
n3=$(count)
[ "$n3" -eq "$n2" ] && pass "and makes no snapshots" || fail "snapshots while broken: $((n3 - n2))"
check "no SELinux denials so far"             'd=$(journalctl -b -o cat | grep "avc:  denied"); test -z "$d" || { echo "$d" | tail -5; exit 1; }'

echo "--- background update download"
vm_ssh 'rpm -qa | sort > /root/rpms-before'
check "download service succeeds"             'systemctl start quill-update-download.service'
vm_ssh 'journalctl -b -u quill-update-download.service -o cat | grep -v "^Starting\|^Finished\|^Consumed" | tail -3 | sed "s/^/info  /"'
check "nothing was installed"                 'rpm -qa | sort | cmp -s - /root/rpms-before'
check "no offline update was scheduled"       'test ! -e /system-update'
# pkcon exits 5 when there is nothing to update.
if vm_ssh 'pkcon -y get-updates >/dev/null 2>&1'; then
    check "the updates are in PackageKit's cache" 'find /var/cache/PackageKit -name "*.rpm" | grep -q .'
else
    echo "info  no updates available right now; cache check skipped"
fi
vm_ssh 'nmcli -g NAME,DEVICE connection show --active | awk -F: "\$2 != \"lo\" {print \$1; exit}" > /root/con; nmcli connection modify "$(cat /root/con)" connection.metered yes; nmcli connection up "$(cat /root/con)" >/dev/null'
check "skips on a metered connection"         'out=$(/usr/libexec/quill-update-download); echo "$out"; echo "$out" | grep -q "metered connection"'
vm_ssh 'nmcli connection modify "$(cat /root/con)" connection.metered unknown; nmcli connection up "$(cat /root/con)" >/dev/null'

echo "--- rollback"
# A fake newest kernel entry (same kernel file) as the default: its modules
# are not in the snapshot, so rollback must pick the real kernel instead.
vm_ssh 'e=$(ls /boot/loader/entries/*.conf | head -1); id=$(basename $e .conf); sed "s/^version .*/version 9.9.9-quilltest/" $e > /boot/loader/entries/${id%-*}-9.9.9-quilltest.conf; grub2-set-default ${id%-*}-9.9.9-quilltest'
check "unknown snapshot is refused"           '! quill-rollback to 99999 --yes'
check "(negative) before rolling back, the marker differs" 'test "$(cat /etc/quill-rollback-test)" = after'
check "rollback to the pre-cowsay snapshot"     "quill-rollback to $base --yes"
check "default kernel switched off the fake"  '! grub2-editenv list | grep -q quilltest'
check "a second rollback before reboot is refused" "quill-rollback to $base --yes 2>&1 | grep -q 'waiting for a reboot'"
check "cleanup keeps the running system"      'quill-rollback cleanup --yes | grep -q "keeping root.old-"'
vm_reboot || { fail "reboot after rollback"; exit 1; }
vm_ssh 'systemctl is-system-running --wait >/dev/null 2>&1; true'
check "/ is the subvolume root again"         'test "$(findmnt -n -o FSROOT /)" = /root'
check "file change was rolled back"           'test "$(cat /etc/quill-rollback-test)" = before'
check "package install was rolled back"       '! rpm -q cowsay'
check "nested subvolume moved across"         'test "$(cat /var/lib/machines/quill-test)" = kept'
check "snapshots still listed"                "snapper -c root list | grep -q 'before cowsay'"
check "no failed units after rollback"        'test -z "$(systemctl --failed --no-legend --plain)" || { systemctl --failed --no-legend --plain; exit 1; }'
check "new transactions still snapshot"       'n=$(snapper --csvout --no-headers -c root list | wc -l); dnf -y -q install cowsay && test $(snapper --csvout --no-headers -c root list | wc -l) -eq $((n + 2))'
check "cleanup deletes the old system"        'quill-rollback cleanup --yes | grep -q "deleted root.old-" && ! btrfs subvolume list / | grep -q root.old-'
vm_ssh 'rm -f /boot/loader/entries/*-9.9.9-quilltest.conf'

exit "$VM_FAIL"
