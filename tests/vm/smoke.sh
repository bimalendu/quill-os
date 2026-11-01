#!/bin/sh
# Boot test: the image boots to a healthy system. Usage: smoke.sh IMAGE.qcow2
# Runs in the builder container (make vm-test).
. "$(dirname "$0")/vm.sh"
img=$1
[ -f "$img" ] || { echo "usage: $0 IMAGE.qcow2"; exit 2; }

vm_create "$img" && vm_start || exit 1
trap vm_stop EXIT
vm_wait || exit 1
# Let boot finish (multi-user services may still be starting when sshd answers).
vm_ssh 'systemctl is-system-running --wait >/dev/null 2>&1; true'

check "os-release says Quill OS"        'grep -qx "NAME=\"Quill OS\"" /etc/os-release'
check "no failed systemd units"         'test -z "$(systemctl --failed --no-legend --plain)" || { systemctl --failed --no-legend --plain; exit 1; }'
check "system state is running"         'test "$(systemctl is-system-running)" = running'
check "SELinux is enforcing"            'test "$(getenforce)" = Enforcing'
check "graphical target is the default" 'test "$(systemctl get-default)" = graphical.target'
check "display manager is active"       'systemctl is-active -q display-manager.service'
check "root is the btrfs subvolume root" 'findmnt -n -o FSTYPE,OPTIONS / | grep -q "^btrfs .*subvol=/root"'
check "Firefox no-AI policy installed"  'test -s /usr/lib64/firefox/distribution/policies.json'
check "/boot files carry SELinux labels"  'test -z "$(restorecon -nRv /boot 2>/dev/null)" || { restorecon -nRv /boot; exit 1; }'
check "no SELinux denials during boot"  'd=$(journalctl -b -o cat | grep "avc:  denied"); test -z "$d" || { echo "$d" | tail -5; exit 1; }'
check "network is online"               'systemctl is-active -q network-online.target && getent hosts fedoraproject.org >/dev/null'

vm_ssh 'echo "info  idle memory used: $(free -m | awk "/^Mem:/ {print \$3}") MiB; boot: $(systemd-analyze 2>/dev/null | head -1)"'
exit "$VM_FAIL"
