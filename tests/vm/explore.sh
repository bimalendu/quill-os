#!/bin/sh
# Development aid: boot the image, optionally install the local quill packages
# (QUILL_INSTALL=1), run the shell commands in tests/vm/explore.cmds in the
# guest and print the output. Not part of any test target.
. "$(dirname "$0")/vm.sh"
img=$1
vm_create "$img" && vm_start || exit 1
trap 'vm_stop; kill $http 2>/dev/null' EXIT
vm_wait || exit 1
vm_ssh 'systemctl is-system-running --wait >/dev/null 2>&1; true'
# TCG is slow: PackageKit's default 45s start timeout is not enough here.
vm_ssh 'mkdir -p /etc/systemd/system/packagekit.service.d; printf "[Service]\nTimeoutStartSec=600\n" > /etc/systemd/system/packagekit.service.d/test.conf; systemctl daemon-reload'
if [ "${QUILL_INSTALL:-0}" = 1 ]; then
    python3 -m http.server --directory /quill-repo 8080 >/dev/null 2>&1 & http=$!
    sleep 1
    vm_ssh 'dnf -y -q --repofrompath=quill,http://10.0.2.2:8080 --setopt=quill.gpgkey=http://10.0.2.2:8080/RPM-GPG-KEY-quill-dev install quill-snapshots quill-updates && systemctl start quill-snapshots-setup.service' || exit 1
fi
vm_ssh 'sh -s' < "$(dirname "$0")/explore.cmds" 2>&1
