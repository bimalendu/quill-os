# Boot a throwaway copy of a Quill OS VM image under QEMU and drive it over SSH.
# Sourced by tests/vm/*.sh inside the builder container. No KVM: QEMU runs with
# TCG (software CPU), which is slow but needs nothing from the host.
#
# The image itself is not modified. Test-only access is given through systemd
# credentials passed as SMBIOS strings:
#   ssh.authorized_keys.root               a throwaway key for root
#   systemd.unit-dropin.multi-user.target  Wants=sshd.service (sshd is off by default)
# Both exist only for the lifetime of the QEMU process.

VM_DIR=${VM_DIR:-/vm}
VM_PORT=${VM_PORT:-2222}
# 2 GiB: QEMU must fit in the 4 GiB build machine with room to spare (3 GiB
# got QEMU OOM-killed during dnf). The guest has zram swap.
VM_MEM=${VM_MEM:-2048}
VM_CPUS=${VM_CPUS:-4}
VM_BOOT_TIMEOUT=${VM_BOOT_TIMEOUT:-900}
EDK2=/usr/share/edk2/aarch64

vm_log() { printf '[vm %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# vm_create BASE.qcow2: a copy-on-write overlay and fresh UEFI variables.
vm_create() {
    mkdir -p "$VM_DIR"
    qemu-img create -q -f qcow2 -b "$1" -F qcow2 "$VM_DIR/disk.qcow2" || return 1
    cp "$EDK2/vars-template-pflash.raw" "$VM_DIR/vars.raw"
    rm -f "$VM_DIR/key" "$VM_DIR/key.pub"
    ssh-keygen -q -t ed25519 -N '' -C quill-vm-test -f "$VM_DIR/key"
}

vm_start() {
    key=$(cut -d' ' -f1,2 "$VM_DIR/key.pub")
    dropin=$(printf '[Unit]\nWants=sshd.service\n' | base64 -w0)
    rm -f "$VM_DIR/qemu.pid"
    qemu-system-aarch64 -machine virt,gic-version=max -cpu max -accel tcg,thread=multi \
        -smp "$VM_CPUS" -m "$VM_MEM" \
        -drive if=pflash,format=raw,readonly=on,file="$EDK2/QEMU_EFI-silent-pflash.raw" \
        -drive if=pflash,format=raw,file="$VM_DIR/vars.raw" \
        -drive if=virtio,format=qcow2,file="$VM_DIR/disk.qcow2",discard=unmap \
        -device virtio-gpu-pci -display none \
        -netdev user,id=n0,hostfwd=tcp:127.0.0.1:"$VM_PORT"-:22 -device virtio-net-pci,netdev=n0 \
        -smbios "type=11,value=io.systemd.credential:ssh.authorized_keys.root=$key" \
        -smbios "type=11,value=io.systemd.credential.binary:systemd.unit-dropin.multi-user.target=$dropin" \
        -serial file:"$VM_DIR/serial.log" -daemonize -pidfile "$VM_DIR/qemu.pid"
}

vm_ssh() {
    ssh -q -i "$VM_DIR/key" -p "$VM_PORT" -o BatchMode=yes -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        root@127.0.0.1 "$@"
}

# vm_wait: until SSH answers. Fails after VM_BOOT_TIMEOUT seconds.
vm_wait() {
    t0=$(date +%s)
    until vm_ssh true 2>/dev/null; do
        if [ $(( $(date +%s) - t0 )) -ge "$VM_BOOT_TIMEOUT" ]; then
            vm_log "no SSH after ${VM_BOOT_TIMEOUT}s; serial console tail:"
            tail -c 3000 "$VM_DIR/serial.log" | tr -d '\r' | grep -v '^$' | tail -20 >&2
            return 1
        fi
        sleep 5
    done
    vm_log "SSH up after $(( $(date +%s) - t0 ))s"
}

vm_running() { [ -f "$VM_DIR/qemu.pid" ] && kill -0 "$(cat "$VM_DIR/qemu.pid")" 2>/dev/null; }

# vm_reboot: reboot the guest and wait for it to come back.
vm_reboot() {
    vm_ssh 'systemctl reboot' 2>/dev/null || true
    t0=$(date +%s)
    while vm_ssh true 2>/dev/null; do
        [ $(( $(date +%s) - t0 )) -lt 120 ] || { vm_log "guest did not go down"; return 1; }
        sleep 2
    done
    vm_wait
}

vm_stop() {
    vm_running || return 0
    vm_ssh 'systemctl poweroff' 2>/dev/null || true
    for _ in $(seq 60); do vm_running || return 0; sleep 2; done
    kill "$(cat "$VM_DIR/qemu.pid")" 2>/dev/null || true
}

# Test bookkeeping shared by the test scripts.
VM_FAIL=0
pass() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; VM_FAIL=1; }
# check "description" guest-shell-command
check() {
    d=$1; shift
    if vm_ssh "$@" >/tmp/check.out 2>&1; then pass "$d"; else fail "$d"; sed 's/^/      /' /tmp/check.out | tail -15; fi
}
