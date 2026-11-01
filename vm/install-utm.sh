#!/bin/sh
# Put the Quill OS VM image into UTM as a new virtual machine, in one command.
#
#   vm/install-utm.sh [install] [--no-start]   import the image and start it
#   vm/install-utm.sh status                    read-only: state, IP, os-release
#   vm/install-utm.sh uninstall                 delete the Quill OS VM (asks first)
#
# Run it from `make install-vm`, `make vm-status` and `make uninstall-vm`.
#
# What it changes: it adds ONE virtual machine named "Quill OS" to UTM. It refuses
# to run if a VM with that name exists. It never addresses any other VM, and it
# acts on the new VM only by the id UTM returned (kept in out/utm-vm-id).
#
# Settings (environment): QUILL_VM_MEMORY in MiB (default 4096), QUILL_VM_CPUS
# (default 4), QUILL_VM_MIN_FREE_GB (default 8). Test hooks: QUILL_UTM_APP,
# QUILL_VM_IMAGE_DIR, QUILL_VM_ID_FILE.

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
NAME="Quill OS"
APP=${QUILL_UTM_APP:-/Applications/UTM.app}
IMGDIR=${QUILL_VM_IMAGE_DIR:-$root/out/VM-KDE}
IDFILE=${QUILL_VM_ID_FILE:-$root/out/utm-vm-id}
MEM=${QUILL_VM_MEMORY:-4096}
CPUS=${QUILL_VM_CPUS:-4}
MINFREE=${QUILL_VM_MIN_FREE_GB:-8}

fail() { echo "vm: $*" >&2; exit 1; }
say()  { echo "vm: $*"; }

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

# osa SCRIPT-TEXT [ARGS...]: run an AppleScript with `on run argv`
osa() {
    s=$1; shift
    printf '%s\n' "$s" > "$work/s.applescript"
    osascript "$work/s.applescript" "$@"
}

list_vms() {
    osa 'on run argv
  tell application "UTM"
    set out to ""
    repeat with v in virtual machines
      set out to out & (name of v) & linefeed
    end repeat
    return out
  end tell
end run'
}

# vm_name ID: the name UTM gives the VM with this id (empty if there is none)
vm_name() {
    osa 'on run argv
  tell application "UTM"
    try
      return name of virtual machine id (item 1 of argv)
    on error
      return ""
    end try
  end tell
end run' "$1"
}

vm_status() {
    osa 'on run argv
  tell application "UTM"
    return (status of virtual machine id (item 1 of argv)) as text
  end tell
end run' "$1"
}

stored_id() {
    [ -s "$IDFILE" ] || fail "no VM recorded in $IDFILE (nothing to do)"
    tr -d '\r\n ' < "$IDFILE"
}

cmd_install() {
    start=yes
    for a in "$@"; do
        case $a in
            --no-start) start=no ;;
            *) fail "unknown option: $a" ;;
        esac
    done

    # ---- pre-checks: nothing is changed until all of them pass ----
    [ "$(uname -s)" = Darwin ] || fail "this installs into UTM on a Mac"
    [ "$(uname -m)" = arm64 ] || fail "this needs an Apple Silicon Mac (found $(uname -m))"
    [ -d "$APP" ] || fail "UTM is not installed ($APP). Get it from https://mac.getutm.app/"
    case $MEM in ''|*[!0-9]*) fail "QUILL_VM_MEMORY must be a number of MiB" ;; esac
    case $CPUS in ''|*[!0-9]*) fail "QUILL_VM_CPUS must be a number" ;; esac
    [ "$MEM" -ge 2048 ] || fail "QUILL_VM_MEMORY=$MEM is too small (2048 MiB minimum)"
    [ "$CPUS" -ge 1 ] || fail "QUILL_VM_CPUS must be at least 1"

    img=$(ls "$IMGDIR"/*.qcow2 2>/dev/null | head -n 1)
    [ -n "$img" ] || fail "no .qcow2 in $IMGDIR (run: make fetch-image PROFILE=VM-KDE)"
    [ -f "$img.sha256" ] || fail "$img.sha256 is missing (run: make fetch-image PROFILE=VM-KDE)"
    say "checking the image against its checksum..."
    ( cd "$(dirname "$img")" && shasum -a 256 -c "$(basename "$img").sha256" >/dev/null 2>&1 ) \
        || fail "the image does not match $img.sha256 (corrupt or changed). Nothing was imported."
    sum=$(cut -d' ' -f1 "$img.sha256")

    free_kb=$(df -Pk "$HOME" | awk 'NR==2 {print $4}')
    [ "$free_kb" -ge $((MINFREE * 1024 * 1024)) ] \
        || fail "less than $MINFREE GB free ($((free_kb / 1024 / 1024)) GB). UTM stores the disk at about 5.4 GB."

    existing=$(list_vms) || fail "could not ask UTM for its VMs. If macOS asked whether Terminal may control UTM, allow it and run this again."
    if printf '%s\n' "$existing" | grep -qxF "$NAME"; then
        fail "UTM already has a VM named \"$NAME\". Nothing was imported. (make uninstall-vm removes the one made by this script.)"
    fi
    [ ! -s "$IDFILE" ] || fail "$IDFILE already records a VM, but UTM does not list it. Delete that file if it is stale."

    say "importing $(basename "$img") as \"$NAME\" ($MEM MiB, $CPUS cores)..."
    id=$(osa 'on run argv
  set vmName to item 1 of argv
  set vmMem to (item 2 of argv) as integer
  set vmCpus to (item 3 of argv) as integer
  set vmImage to item 4 of argv
  set vmNotes to item 5 of argv
  tell application "UTM"
    set vm to make new virtual machine with properties {backend:qemu, configuration:{name:vmName, architecture:"aarch64", memory:vmMem, cpu cores:vmCpus, uefi:true, hypervisor:true, drives:{{removable:false, interface:VirtIO, source:POSIX file vmImage}}, displays:{{hardware:"virtio-gpu-gl-pci"}}, network interfaces:{{mode:shared}}, notes:vmNotes}}
    return id of vm
  end tell
end run' "$NAME" "$MEM" "$CPUS" "$img" "Quill OS VM-KDE $sum") || fail "UTM could not create the VM. Nothing else was changed."
    [ -n "$id" ] || fail "UTM returned no id for the new VM"

    mkdir -p "$(dirname "$IDFILE")"
    printf '%s\n' "$id" > "$IDFILE"
    [ "$(vm_name "$id")" = "$NAME" ] || fail "UTM does not list the new VM under id $id (kept in $IDFILE). Check UTM."
    say "created \"$NAME\" (id $id, saved in $IDFILE)"

    if [ "$start" = yes ]; then
        osa 'on run argv
  tell application "UTM" to start virtual machine id (item 1 of argv)
end run' "$id" || fail "the VM was created but did not start. Start it from UTM."
        say "started. Expect: GRUB, then Plasma Setup (create your user), the Quill login, then Quill Setup."
    else
        say "not started (--no-start). Start it from UTM, or: make vm-status"
    fi
}

cmd_status() {
    id=$(stored_id) || exit 1
    n=$(vm_name "$id")
    [ "$n" = "$NAME" ] || fail "UTM has no \"$NAME\" VM with id $id"
    st=$(vm_status "$id")
    say "$NAME: $st (id $id)"
    [ "$st" = started ] || { say "start it from UTM to see its address"; return 0; }
    ip=$(osa 'on run argv
  tell application "UTM"
    try
      set addrs to query ip virtual machine id (item 1 of argv)
      set AppleScript'"'"'s text item delimiters to " "
      return addrs as text
    on error
      return ""
    end try
  end tell
end run' "$id")
    if [ -n "$ip" ]; then say "address: $ip"; else say "no address yet (the guest agent answers once the desktop is up)"; fi
    rel=$(osa 'on run argv
  tell application "UTM"
    try
      set p to execute virtual machine id (item 1 of argv) at "/usr/bin/cat" with arguments {"/etc/os-release"} with output capturing
      delay 1
      set r to get result of p
      return output text of r
    on error
      return ""
    end try
  end tell
end run' "$id")
    if [ -n "$rel" ]; then printf '%s\n' "$rel" | grep -E '^(NAME|VERSION|PRETTY_NAME)='; else say "the guest agent is not answering yet"; fi
}

cmd_uninstall() {
    id=$(stored_id) || exit 1
    n=$(vm_name "$id")
    [ "$n" = "$NAME" ] || fail "the VM with id $id is named \"$n\", not \"$NAME\". Nothing was deleted."
    st=$(vm_status "$id")
    [ "$st" = stopped ] || fail "\"$NAME\" is $st. Shut it down first, then run this again. Nothing was deleted."
    printf 'This deletes the VM "%s" and its disk (id %s). Type yes to continue: ' "$NAME" "$id"
    read -r ans
    [ "$ans" = yes ] || { say "cancelled. Nothing was deleted."; return 0; }
    osa 'on run argv
  tell application "UTM" to delete virtual machine id (item 1 of argv)
end run' "$id" || fail "UTM could not delete the VM"
    rm -f "$IDFILE"
    say "deleted \"$NAME\""
}

case ${1:-install} in
    install) [ $# -gt 0 ] && shift; cmd_install "$@" ;;
    --no-start) cmd_install "$@" ;;
    status) cmd_status ;;
    uninstall) cmd_uninstall ;;
    -h|--help) sed -n 2,13p "$0" ;;
    *) fail "usage: install-utm.sh [install [--no-start]|status|uninstall]" ;;
esac
